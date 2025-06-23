"""
Player data and statistics module for ESPN Fantasy Baseball MCP Server
Handles player stats, free agents, and player queries
"""

from typing import Dict, Any, Optional, List, Generator, Tuple
import traceback
from rapidfuzz import fuzz
from baseball_mcp.utils import league_service, handle_error, player_to_dict, log_error
from baseball_mcp.auth import auth_service

def fuzzy_match_name(search_term: str, player_name: str, threshold: int = 80) -> Tuple[bool, int]:
    """Perform fuzzy matching between a search term and a player name.

    Args:
        search_term: The search term to match against
        player_name: The player's name to search in
        threshold: Minimum score (0-100) to consider it a match

    Returns:
        Tuple of (is_match, score) where score is the match percentage (0-100)
    """
    if not search_term or not player_name:
        return False, 0

    # Simple case-insensitive substring match (fast path)
    search_lower = search_term.lower()
    if search_lower in player_name.lower():
        return True, 100

    # Try different fuzzy matching strategies
    # 1. Partial ratio (best for partial name matches)
    score = fuzz.partial_ratio(search_lower, player_name.lower())
    if score >= threshold:
        return True, score

    # 2. Token set ratio (handles word order differences)
    score = fuzz.token_set_ratio(search_lower, player_name.lower())
    if score >= threshold:
        return True, score

    # 3. Try matching first name only
    search_parts = search_lower.split()
    name_parts = player_name.lower().split()

    if len(search_parts) > 1 and len(name_parts) > 1:
        # Try matching just first names
        if search_parts[0] == name_parts[0]:
            return True, 85  # First name match is good enough

    return False, score

def get_paginated_free_agents(league, batch_size: int = 100, max_players: int = 1000) -> Generator[Any, None, None]:
    """Generator that yields free agents in batches to handle pagination.

    Args:
        league: The league object to fetch free agents from
        batch_size: Number of players to fetch in each batch (default 100)
        max_players: Maximum total players to fetch (default 1000)

    Yields:
        Player objects one at a time
    """
    offset = 0
    total_players = 0

    while total_players < max_players:
        try:
            batch = league.free_agents(size=batch_size, offset=offset)
            if not batch:
                break

            for player in batch:
                if total_players >= max_players:
                    return
                yield player
                total_players += 1

            offset += batch_size

            # If we got fewer players than requested, we've reached the end
            if len(batch) < batch_size:
                break

        except Exception as e:
            log_error(f"Error fetching free agents batch (offset={offset}): {str(e)}")
            break

def get_player_stats(league_id: int, player_name: str, year: Optional[int] = None,
                    session_id: str = "default_session") -> Dict[str, Any]:
    """
    Get detailed statistics for a specific player.
    
    Args:
        league_id: The ESPN fantasy baseball league ID
        player_name: Name of the player to search for
        year: Optional year for historical data (defaults to current season)
        session_id: Session identifier for authentication
    
    Returns:
        Dictionary containing player information and statistics
    """
    try:
        # Get credentials for this session
        credentials = auth_service.get_credentials(session_id)
        espn_s2 = credentials.get('espn_s2') if credentials else None
        swid = credentials.get('swid') if credentials else None
        
        # Get league instance
        league = league_service.get_league(league_id, year, espn_s2, swid)
        
        # Search for player in team rosters first
        player = None
        team_found = None
        
        for team in league.teams:
            for roster_player in team.roster:
                if player_name.lower() in roster_player.name.lower():
                    player = roster_player
                    team_found = team
                    break
            if player:
                break
        
        # If not found in rosters, search free agents with pagination & fuzzy matching
        if not player:
            try:
                for fa_player in get_paginated_free_agents(league, batch_size=200, max_players=1000):
                    try:
                        player_name_lower = player_name.lower()
                        fa_name = getattr(fa_player, 'name', '')

                        # First try exact match for performance
                        if player_name_lower in fa_name.lower():
                            player = fa_player
                            break

                        # Then try fuzzy match if exact match fails
                        is_match, score = fuzzy_match_name(player_name, fa_name, threshold=80)
                        if is_match:
                            log_error(f"Fuzzy match found: '{player_name}' -> '{fa_name}' (score: {score})")
                            player = fa_player
                            break

                    except Exception as player_error:
                        log_error(f"Error processing player {getattr(fa_player, 'name', 'unknown')}: {str(player_error)}")
                        continue

            except Exception as e:
                error_msg = f"Error searching free agents: {str(e)}"
                log_error(error_msg)
                log_error(f"Stack trace: {traceback.format_exc()}")
                return {"error": error_msg, "details": "Failed to search free agents"}
        
        if not player:
            return {"error": f"Player '{player_name}' not found in league {league_id}"}
        
        # Convert player to dictionary
        player_stats = player_to_dict(player)
        
        # Add team information if player is on a roster
        if team_found:
            player_stats["fantasy_team"] = {
                "team_id": getattr(team_found, "team_id", None),
                "team_name": getattr(team_found, "team_name", "Unknown"),
                "owner": getattr(team_found, "owner", "Unknown")
            }
        else:
            player_stats["fantasy_team"] = None
            player_stats["status"] = "FREE_AGENT"
        
        # Add weekly and season stats if available
        if hasattr(player, "stats") and player.stats:
            from baseball_mcp.metadata import STATS_MAP
            
            weekly_stats: Dict[str, Any] = {}
            season_stats: Dict[str, Any] = {}
            
            for period, period_stats in player.stats.items():
                converted_stats = {}
                for stat_id, value in period_stats.items():
                    stat_name = STATS_MAP.get(stat_id, f"stat_{stat_id}")
                    converted_stats[stat_name] = value
                
                if "week" in str(period) or "recent" in str(period):
                    weekly_stats[str(period)] = converted_stats
                else:
                    season_stats[str(period)] = converted_stats
            
            if weekly_stats:
                player_stats["weekly_stats"] = weekly_stats
            if season_stats:
                player_stats["season_stats"] = season_stats
        
        # Add ownership information for free agents
        if hasattr(player, "percent_owned"):
            player_stats["ownership"] = {
                "percent_owned": player.percent_owned,
                "percent_started": getattr(player, "percent_started", None)
            }
        
        return player_stats
    
    except Exception as e:
        return handle_error(e, "get_player_stats")

def get_free_agents(league_id: int, week: Optional[int] = None, position: Optional[str] = None,
                   position_id: Optional[int] = None, limit: int = 50, year: Optional[int] = None,
                   session_id: str = "default_session") -> List[Dict[str, Any]]:
    """
    Get list of available free agents with filtering options.
    
    Args:
        league_id: The ESPN fantasy baseball league ID
        week: Week for which to get stats (defaults to current week)
        position: Position filter (e.g., "C", "1B", "OF", "SP", "RP")
        position_id: ESPN position ID filter (alternative to position name)
        limit: Maximum number of players to return (default 50)
        year: Optional year for historical data (defaults to current season)
        session_id: Session identifier for authentication
    
    Returns:
        List of free agent player dictionaries
    """
    try:
        # Get credentials for this session
        credentials = auth_service.get_credentials(session_id)
        espn_s2 = credentials.get('espn_s2') if credentials else None
        swid = credentials.get('swid') if credentials else None
        
        # Get league instance
        league = league_service.get_league(league_id, year, espn_s2, swid)
        
        # Build free agents query parameters
        fa_params = {"size": min(limit, 100)}  # ESPN typically limits to 100
        
        if week is not None:
            fa_params["week"] = week
        
        # Handle position filtering
        if position_id is not None:
            fa_params["position_id"] = position_id
        elif position is not None:
            # Convert position name to position ID if needed
            from baseball_mcp.metadata import POSITION_MAP
            # Create reverse mapping
            position_name_to_id = {v: k for k, v in POSITION_MAP.items() if v == position}
            if position_name_to_id:
                fa_params["position_id"] = list(position_name_to_id.keys())[0]
            else:
                # If exact match not found, try to find by string matching
                fa_params["position"] = position
        
        # Get free agents from league
        try:
            free_agents = league.free_agents(**fa_params)
        except Exception:
            # If parameterized call fails, try with just size
            free_agents = league.free_agents(size=limit)
        
        # Process free agents
        processed_agents = []
        for player in free_agents:
            try:
                player_dict = player_to_dict(player)
                
                # Add additional free agent specific information
                player_dict["status"] = "FREE_AGENT"
                
                # Add fantasy relevance metrics if available
                if hasattr(player, "percent_owned"):
                    player_dict["ownership_info"] = {
                        "percent_owned": player.percent_owned,
                        "percent_started": getattr(player, "percent_started", None),
                        "percent_change": getattr(player, "percent_change", None)
                    }
                
                # Filter by position if specified and not filtered by API
                if position and not position_id:
                    eligible_positions = player_dict.get("eligible_positions", [])
                    if position not in eligible_positions:
                        continue
                
                processed_agents.append(player_dict)
                
                # Stop if we've reached the limit
                if len(processed_agents) >= limit:
                    break
                    
            except Exception as e:
                # If we can't process an individual player, log and continue
                log_error(f"Error processing free agent: {str(e)}")
                continue
        
        return processed_agents
    
    except Exception as e:
        return [handle_error(e, "get_free_agents")]

def get_top_performers(league_id: int, position: Optional[str] = None, limit: int = 20,
                      metric: str = "points", year: Optional[int] = None,
                      session_id: str = "default_session") -> List[Dict[str, Any]]:
    """
    Get top performing players across all teams in the league.
    
    Args:
        league_id: The ESPN fantasy baseball league ID
        position: Position filter (e.g., "C", "1B", "OF", "SP", "RP")
        limit: Maximum number of players to return (default 20)
        metric: Metric to sort by ("points", "batting_average", "home_runs", "era", etc.)
        year: Optional year for historical data (defaults to current season)
        session_id: Session identifier for authentication
    
    Returns:
        List of top performing player dictionaries
    """
    try:
        # Get credentials for this session
        credentials = auth_service.get_credentials(session_id)
        espn_s2 = credentials.get('espn_s2') if credentials else None
        swid = credentials.get('swid') if credentials else None
        
        # Get league instance
        league = league_service.get_league(league_id, year, espn_s2, swid)
        
        # Collect all players from all teams
        all_players = []
        for team in league.teams:
            for player in team.roster:
                player_dict = player_to_dict(player)
                player_dict["fantasy_team"] = {
                    "team_id": getattr(team, "team_id", None),
                    "team_name": getattr(team, "team_name", "Unknown"),
                    "owner": getattr(team, "owner", "Unknown")
                }
                all_players.append(player_dict)
        
        # Filter by position if specified
        if position:
            filtered_players = []
            for player in all_players:
                eligible_positions = player.get("eligible_positions", [])
                if position in eligible_positions or player.get("position") == position:
                    filtered_players.append(player)
            all_players = filtered_players
        
        # Sort by the specified metric
        def get_sort_value(player):
            if metric == "points":
                return player.get("total_points", 0)
            elif metric in player.get("stats", {}):
                return player["stats"].get(metric, 0)
            else:
                # Try common stat mappings
                stat_mappings = {
                    "batting_average": "AVG",
                    "home_runs": "HR",
                    "rbi": "RBI",
                    "stolen_bases": "SB",
                    "era": "ERA",
                    "whip": "WHIP",
                    "strikeouts": "K",
                    "wins": "W",
                    "saves": "SV"
                }
                mapped_stat = stat_mappings.get(metric.lower())
                if mapped_stat and mapped_stat in player.get("stats", {}):
                    # For ERA and WHIP, lower is better
                    value = player["stats"][mapped_stat]
                    if mapped_stat in ["ERA", "WHIP"]:
                        return -value if value > 0 else 0  # Negative for reverse sort
                    return value
                return 0
        
        # Sort players by the metric (descending for most stats)
        sorted_players = sorted(all_players, key=get_sort_value, reverse=True)
        
        # Return top performers
        return sorted_players[:limit]
    
    except Exception as e:
        return [handle_error(e, "get_top_performers")]

def search_players(league_id: int, search_term: str, include_rostered: bool = True,
                  include_free_agents: bool = True, year: Optional[int] = None,
                  session_id: str = "default_session") -> List[Dict[str, Any]]:
    """
    Search for players by name across rosters and free agents.
    
    Args:
        league_id: The ESPN fantasy baseball league ID
        search_term: Partial or full player name to search for
        include_rostered: Whether to include players on team rosters
        include_free_agents: Whether to include free agents
        year: Optional year for historical data (defaults to current season)
        session_id: Session identifier for authentication
    
    Returns:
        List of matching player dictionaries
    """
    try:
        # Get credentials for this session
        credentials = auth_service.get_credentials(session_id)
        espn_s2 = credentials.get('espn_s2') if credentials else None
        swid = credentials.get('swid') if credentials else None
        
        # Get league instance
        league = league_service.get_league(league_id, year, espn_s2, swid)
        
        matching_players = []
        search_lower = search_term.lower()
        
        # Search rostered players first
        if include_rostered:
            for team in league.teams:
                for player in team.roster:
                    if search_lower in player.name.lower():
                        player_dict = player_to_dict(player)
                        player_dict.update({
                            "status": "ROSTERED",
                            "fantasy_team": {
                                "team_id": getattr(team, "team_id", None),
                                "team_name": getattr(team, "team_name", "Unknown"),
                                "owner": getattr(team, "owner", "Unknown")
                            },
                            "match_score": 100
                        })
                        matching_players.append(player_dict)
        
        # Search free agents with pagination & fuzzy matching
        if include_free_agents and len(matching_players) < 50:
            try:
                for player in get_paginated_free_agents(league, batch_size=200, max_players=1000):
                    try:
                        player_name = getattr(player, 'name', '')
                        is_match, score = fuzzy_match_name(search_term, player_name, threshold=80)
                        if is_match:
                            player_dict = player_to_dict(player)
                            player_dict.update({
                                "status": "FREE_AGENT",
                                "match_score": score,
                                "fantasy_team": None
                            })
                            matching_players.append(player_dict)
                            if len(matching_players) >= 50:
                                break
                    except Exception as player_error:
                        log_error(f"Error processing player {getattr(player, 'name', 'unknown')}: {str(player_error)}")
                        continue
            except Exception as e:
                log_error(f"Error searching free agents: {str(e)}")
        
        # Deduplicate by player ID keeping highest score
        player_map: Dict[Any, Dict[str, Any]] = {}
        for player in matching_players:
            pid = player.get('player_id')
            if pid is None:
                continue
            current_best = player_map.get(pid)
            if current_best is None or player.get('match_score', 0) > current_best.get('match_score', 0):
                player_map[pid] = player
        
        unique_players = list(player_map.values())
        unique_players.sort(key=lambda p: (-p.get('match_score', 0), p.get('name', '').lower()))
        return unique_players
    
    except Exception as e:
        return [handle_error(e, "search_players")]

def get_waiver_claims(league_id: int, limit: int = 25, year: Optional[int] = None,
                     session_id: str = "default_session") -> List[Dict[str, Any]]:
    """
    Get recent waiver claims and FAAB bids information.
    
    Args:
        league_id: The ESPN fantasy baseball league ID
        limit: Maximum number of claims to return
        year: Optional year for historical data (defaults to current season)
        session_id: Session identifier for authentication
    
    Returns:
        List of waiver claim dictionaries
    """
    try:
        # Get credentials for this session
        credentials = auth_service.get_credentials(session_id)
        espn_s2 = credentials.get('espn_s2') if credentials else None
        swid = credentials.get('swid') if credentials else None
        
        # Get league instance
        league = league_service.get_league(league_id, year, espn_s2, swid)
        
        # Try to get waiver claims through different ESPN API methods
        waiver_claims = []
        
        # Method 1: Check if league has a waiver method
        if hasattr(league, 'waiver_claims'):
            try:
                claims = league.waiver_claims(limit=limit)
                for claim in claims:
                    try:
                        claim_dict = {
                            "type": "WAIVER_CLAIM",
                            "player": player_to_dict(claim.player) if hasattr(claim, 'player') else None,
                            "team": claim.team.team_name if hasattr(claim, 'team') else None,
                            "bid_amount": getattr(claim, 'bid_amount', None),
                            "priority": getattr(claim, 'priority', None),
                            "status": getattr(claim, 'status', 'UNKNOWN'),
                            "date": getattr(claim, 'date', None)
                        }
                        waiver_claims.append(claim_dict)
                    except Exception as e:
                        log_error(f"Error processing waiver claim: {str(e)}")
                        continue
            except Exception as e:
                log_error(f"Error fetching waiver claims: {str(e)}")
        
        # Method 2: Fallback to activity filtering
        if not waiver_claims:
            from baseball_mcp.transactions import get_waiver_activity
            waiver_activities = get_waiver_activity(league_id, limit, year, session_id)
            
            for activity in waiver_activities:
                if activity.get("source") == "WAIVERS":
                    waiver_claims.append({
                        "type": "WAIVER_ACTIVITY",
                        "activity_type": activity.get("type"),
                        "player": activity.get("added_player"),
                        "team": activity.get("team", {}).get("team_name"),
                        "date": activity.get("date"),
                        "source": "ACTIVITY_LOG"
                    })
        
        return waiver_claims
    
    except Exception as e:
        return [handle_error(e, "get_waiver_claims")]