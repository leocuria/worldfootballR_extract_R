#' Get match lineups
#'
#' Returns lineups for home and away teams for a selected match
#'
#' @param match_url the fbref.com URL for the required match
#'
#' @return returns a dataframe with the team lineups for a selected match
#'
#' @importFrom magrittr %>%
#' @importFrom rlang .data
#'
#' @export
#'
#' @examples
#' \dontrun{
#' match <- get_match_urls(country = "AUS", gender = "F", season_end_year = 2021, tier = "1st")[1]
#' get_match_lineups(match_url = match)
#' }

get_match_lineups <- function(match_url) {
  print("Scraping lineups")

  get_each_match_lineup <- function(match_url) {

    match_page <- tryCatch(xml2::read_html(match_url), error = function(e) NA)

    if(!is.na(match_page)) {
      match_date <- match_page %>% rvest::html_nodes(".venuetime") %>% rvest::html_attr("data-venue-date")

      lineups <- match_page %>% rvest::html_nodes(".lineup") %>% rvest::html_nodes("table")

      home <- 1
      away <- 2

      get_each_lineup <- function(home_away) {
        lineup <- lineups[home_away] %>% rvest::html_table() %>% data.frame()
        formation <- names(lineup)[1] %>% gsub(".*\\.\\.", "", .) %>% stringr::str_extract_all(., "[[:digit:]]") %>% unlist() %>% paste(collapse = "-")
        tryCatch( {team <- match_page %>% rvest::html_nodes("div:nth-child(1) div strong a") %>% rvest::html_text() %>% .[home_away]}, error = function(e) {team <- NA})

        bench_index <- which(lineup[,1] == "Bench")

        lineup <- lineup[1:(bench_index-1),] %>% dplyr::mutate(Starting = "Pitch") %>%
          dplyr::bind_rows(
            lineup[(bench_index+1):nrow(lineup),] %>% dplyr::mutate(Starting = "Bench")
          )

        lineup <- lineup %>%
          dplyr::mutate(Matchday = match_date,
                        Team = team,
                        Formation = formation)

        names(lineup) <- c("Player_Num", "Player_Name", "Starting", "Matchday", "Team", "Formation")

        all_tables <- match_page %>%
          rvest::html_nodes(".table_container")

        stat_df <- all_tables[which(stringr::str_detect(all_tables %>% rvest::html_attr("id"), "summary$"))] %>%
          rvest::html_nodes("table")

        if(home_away == 1) {
          home_or_away <- "Home"
        } else {
          home_or_away <- "Away"
        }

        additional_info <- stat_df[home_away]%>% rvest::html_table() %>% data.frame()

        additional_info <- additional_info %>%
          .clean_match_advanced_stats_data() %>%
          dplyr::filter(!is.na(.data$Player_Num)) %>%
          dplyr::bind_cols(Team=team, Home_Away=home_or_away, .) %>%
          dplyr::select(.data$Team, .data$Home_Away, .data$Player, .data$Player_Num, .data$Nation, .data$Pos, .data$Age, .data$Min, .data$Gls, .data$Ast, .data$CrdY, .data$CrdR) %>%
          dplyr::mutate(Player_Num = as.character(.data$Player_Num))


        lineup <- lineup %>%
          dplyr::mutate(Player_Num = as.character(.data$Player_Num)) %>%
          dplyr::left_join(additional_info, by = c("Team", "Player_Name" = "Player", "Player_Num")) %>%
          dplyr::mutate(Home_Away = ifelse(is.na(.data$Home_Away), home_or_away, .data$Home_Away)) %>%
          dplyr::select(.data$Matchday, .data$Team, .data$Home_Away, .data$Formation, .data$Player_Num, .data$Player_Name, .data$Starting, dplyr::everything()) %>%
          dplyr::mutate(Matchday = lubridate::ymd(.data$Matchday))


        return(lineup)
      }

      all_lineup <- c(home, away) %>%
        purrr::map_df(get_each_lineup)

    } else {
      print(glue::glue("Lineups not available for {match_url}"))
      all_lineup <- data.frame()
    }

    return(all_lineup)
  }
  all_lineups <- match_url %>%
    purrr::map_df(get_each_match_lineup)

  return(all_lineups)
}
