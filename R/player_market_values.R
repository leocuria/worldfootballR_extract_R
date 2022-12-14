#' Get player market values
#'
#' Returns data frame of player valuations (in Euros) from transfermarkt.com
#'
#' @param country_name the country of the league's players
#' @param start_year the start year of the season (2020 for the 20/21 season)
#' @param league_url league url from transfermarkt.com. To be used when country_name not avalilable in main function
#'
#' @return returns a dataframe of player valuations for country/seasons
#'
#' @importFrom magrittr %>%
#' @importFrom rlang .data
#' @importFrom utils read.csv
#'
#' @export
#'
#' @examples
#' \dontrun{
#' get_player_market_values(country_name = "England", start_year = c(2019, 2020))
#' }

get_player_market_values <- function(country_name, start_year, league_url = NA) {

  print("Extracting player market values...")

  main_url <- "https://www.transfermarkt.com"

  if(is.na(league_url)) {
    meta_df <- read.csv(url("https://raw.githubusercontent.com/JaseZiv/worldfootballR_data/master/raw-data/transfermarkt_leagues/main_comp_seasons.csv"),
                        stringsAsFactors = F)

    tryCatch({meta_df_seasons <- meta_df %>%
      dplyr::filter(.data$country %in% country_name, .data$season_start_year %in% start_year)}, error = function(e) {meta_df_seasons <- data.frame()})

    if(nrow(meta_df_seasons) == 0) {
      stop(glue::glue("Country {country_name} or season {start_year} not found. Check that the country and season exists at https://github.com/JaseZiv/worldfootballR_data/blob/master/raw-data/transfermarkt_leagues/main_comp_seasons.csv"))
    }

  } else {

    tryCatch({league_page <- xml2::read_html(league_url)}, error = function(e) {league_page <- c()})

    if(length(league_page) == 0) {
      stop(glue::glue("League URL(s) {league_url} not found. Please check transfermarkt.com for the correct league URL"))

    }

    comp_name <- league_page %>% rvest::html_nodes(".spielername-profil") %>% rvest::html_text()

    country <- league_page %>% rvest::html_nodes(".miniflagge")
    country <- xml2::xml_attrs(country[[1]])[["title"]]

    seasons <- league_page %>% rvest::html_nodes(".chzn-select") %>% rvest::html_nodes("option")

    season_start_year <- c()
    for(each_season in seasons) {
      season_start_year <- c(season_start_year, xml2::xml_attrs(each_season)[["value"]])
    }

    season_urls <- paste0(league_url, "/plus/?saison_id=", season_start_year)

    meta_df_seasons <- data.frame(comp_name=as.character(comp_name), region=NA_character_, country=as.character(country), comp_url=as.character(league_url), season_start_year=as.numeric(season_start_year), season_urls=as.character(season_urls))

    tryCatch({meta_df_seasons <- meta_df_seasons %>%
      dplyr::filter(.data$season_start_year %in% start_year)}, error = function(e) {meta_df_seasons <- data.frame()})

    if(nrow(meta_df_seasons) == 0) {
      stop(glue::glue("League URL(s) {league_urls} or seasons {start_year} not found. Please check transfermarkt.com for the correct league URL"))

    }

  }

  all_seasons_urls <- meta_df_seasons$season_urls

  all_seasons_df <- data.frame()

  for(each_season in all_seasons_urls) {

    season_page <- xml2::read_html(each_season)

    team_urls <- season_page %>%
      rvest::html_nodes(".items") %>%
      rvest::html_nodes(".vereinprofil_tooltip") %>% rvest::html_attr("href") %>%
      unique() %>% paste0(main_url, .)

    team_urls <- gsub("startseite", "kader", team_urls) %>%
      paste0(., "/plus/1")




    # Get Teams ---------------------------------------------------------------

    league_season_df <- data.frame()

    for(each_team in team_urls) {

      team_page <- xml2::read_html(each_team)

      team_data <- team_page %>% rvest::html_nodes("#yw1") %>% rvest::html_nodes(".items") %>% rvest::html_node("tbody")

      # team name
      squad <- team_page %>% rvest::html_node(".dataName") %>% rvest::html_text() %>% stringr::str_squish()
      # numbers
      player_num <- team_data %>% rvest::html_nodes(".rn_nummer") %>% rvest::html_text()
      # player names
      player_name <- team_data %>% rvest::html_nodes(".hide-for-small") %>% rvest::html_nodes(".spielprofil_tooltip") %>% rvest::html_text()
      # player_url
      player_url <- team_data %>% rvest::html_nodes(".hide-for-small") %>%
        rvest::html_nodes(".spielprofil_tooltip") %>% rvest::html_attr("href") %>%
        paste0(main_url, .)
      # player position
      player_position <- team_data %>% rvest::html_nodes(".inline-table tr+ tr td") %>% rvest::html_text()
      # birthdate
      player_birthday <- team_data %>% rvest::html_nodes(".posrela+ .zentriert") %>% rvest::html_text()
      # player_nationality
      player_nationality <- c()
      player_nat <- team_data %>% rvest::html_nodes(".flaggenrahmen:nth-child(1)")
      for(i in 1:length(player_nat)) {
        player_nationality <- c(player_nationality, xml2::xml_attrs(player_nat[[i]])[["title"]])
      }
      # value
      player_market_value <- team_data %>% rvest::html_nodes(".rechts.hauptlink") %>% rvest::html_text()

      team_df <- cbind(each_season, squad, player_num, player_name, player_url, player_position, player_birthday, player_nationality, player_market_value) %>% data.frame()
      team_df <- team_df %>%
        dplyr::rename(season_urls=each_season)

      league_season_df <- rbind(league_season_df, team_df)

    }

    all_seasons_df <- rbind(all_seasons_df, league_season_df)

  }

  all_seasons_df <- meta_df_seasons %>%
    dplyr::left_join(all_seasons_df, by = "season_urls")

  all_seasons_df <- all_seasons_df %>%
    dplyr::mutate(player_market_value_euro = mapply(.convert_value_to_numeric, player_market_value)) %>%
    tidyr::separate(., player_birthday, into = c("Month", "Day", "Year", "player_age"), sep = " ", remove = F) %>%
    dplyr::mutate(Day = gsub(",", "", .data$Day) %>% as.numeric(),
                  Year = as.numeric(.data$Year),
                  Month = match(.data$Month, month.abb),
                  player_dob = lubridate::ymd(paste(.data$Year, .data$Month, .data$Day, sep = "-"))) %>%
    dplyr::mutate(player_age = as.numeric(gsub("\\D", "", .data$player_age))) %>%
    dplyr::select(.data$comp_name, .data$region, .data$country, .data$season_start_year, .data$squad, .data$player_num, .data$player_name, .data$player_position, .data$player_dob, .data$player_age, .data$player_nationality, .data$player_market_value_euro, .data$player_url)


  return(all_seasons_df)
}
