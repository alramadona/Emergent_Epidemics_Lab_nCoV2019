#SV Scarpino
#nCov2019
#Jan 24th 2020

###########
#Libraries#
###########
library(leaflet)
library(RColorBrewer)
library(scales)
library(lattice)
library(dplyr)
library(leaflet.mapboxgl)
library(leaflet.extras)

########
#Server#
########
function(input, output, session) {
  ##########
  #Map View#
  ##########
  
  output$map <- renderLeaflet({
    leaflet() %>%
      addMapboxGL(
        style = map_url,
        setView = FALSE
      ) %>%
      setView(lng = 17, lat = 15, zoom = 3)
  })
  
  #add cases from filtered view
  observeEvent(c(input$wuhan_resident, input$travel_history_location, input$country, input$confirmed),{
    filter_data <- make_filter_data()

    first_date <- min(filter_data$date_confirmation, na.rm = TRUE)
    first_date_plot <- format(first_date, format = "%d-%m-%Y")
    filter_data_china <- NULL
    
    china_filt <- which(filter_data$province == "Hubei")
    if(length(china_filt) > 0){
      filter_data_china <- filter_data[china_filt, ]
      filter_data <- filter_data[-china_filt,]
    }
    
    if(nrow(filter_data) > 0){
      colorData <-  Sys.time() - filter_data$date_confirmation
      colorData <- round(as.numeric(colorData, units = "days"), 0)
      
      pal <- colorFactor(palette = rev(c("#4292c6", "#08519c", "#a50f15", "#67000d")), domain = colorData)
      
      node_radii <- 6 - colorData
      node_radii[which(node_radii > 8)] <- 6
      node_radii[which(node_radii < 3)] <- 3
      node_radii[which(is.na(node_radii) == TRUE)] <- 2
      
      node_opac <- node_radii/max(node_radii, na.rm = TRUE)
      
      filter_data$node_radii <- node_radii
      
      if(is.finite(max(colorData, na.rm = TRUE)) == FALSE){
        legend_vals <- NA
      }else{
        legend_vals <- round(seq(1, max(colorData, na.rm = TRUE), length.out = 10),0)
      }
      
      leafletProxy("map", data = filter_data) %>%
        clearMarkers() %>%
        clearPopups() %>%
        clearGroup(group = "heatmap-china") %>% 
        addCircleMarkers(lng = ~longitude, lat = ~latitude, layerId = ~ID, radius= ~node_radii, stroke=FALSE, fillOpacity=node_opac, fillColor=pal(colorData)) %>%
        addLegend(position = "bottomleft", pal=pal, values=legend_vals, title=paste0("Days since confirmation"), layerId="colorLegend")
    }
    
    if(is.null(filter_data_china) == FALSE & nrow(filter_data) == 0){
      leafletProxy("map", data = filter_data_china[1:10000,]) %>%
        clearMarkers() %>%
        clearPopups() %>%
        clearGroup(group = "heatmap-china") %>% 
        addHeatmap(lng=~longitude, lat=~latitude, group = "heatmap-china", gradient = "OrRd", radius = 10, blur = 20)
    }
    
    if(is.null(filter_data_china) == FALSE & nrow(filter_data) > 0){
      leafletProxy("map", data = filter_data_china[1:10000,]) %>%
        clearGroup(group = "heatmap-china") %>% 
        addHeatmap(lng=~longitude, lat=~latitude, group = "heatmap-china", gradient = "OrRd", radius = 10, blur = 20)
    }
  })
  
  #update data
  output$last_updated <- reactive({
    filter_data <- make_filter_data() #this just triggers an update if the data refresh
    last_update <- readLines("data/last_data_update.txt")
    last_update_day <- strptime(substr(last_update, 1, 10), format = "%Y-%m-%d")

    paste0("Last Updated: ", format(last_update_day, format = "%b %d, %Y"))
  })
  
  #make filtered view
  make_filter_data <- reactive({
    if(is.null(x = input$wuhan_resident) == TRUE){
      df <- full_data
    }else{
      df <- full_data %>%
        filter(
          lives_in_Wuhan %in% input$wuhan_resident
        )
    }
  
    if(is.null(x = input$travel_history_location) == TRUE){
      df2 <- df
    }else{
      df2 <- df %>%
        filter(
          travel_history_location %in% input$travel_history_location
        )
    }
    
    if(is.null(x = input$country) == TRUE){
      df3 <- df2
    }else{
      df3 <- df2 %>%
        filter(
          country %in% input$country
        )
    }
    
    if(is.null(x = input$confirmed) == TRUE | input$confirmed == "No"){
      df4 <- df3
    }else{
      df4 <- df3 %>%
        filter(
          !is.na(date_confirmation)
        )
    }
    
    return(df4)
  })
  
  #show a popup at the given location
  showCasePopup <- function(case_id, lat, lng) {
    filter_data <- make_filter_data()
    
    selected_case <- filter_data[filter_data$ID == case_id,]
    
    main_display <- NULL
    if(is.na(selected_case$city) ==FALSE){
      main_display <- as.character(selected_case$city)
    }
    
    if(is.na(selected_case$province) == FALSE){
      if(length(main_display) == 0){
        main_display <- as.character(selected_case$province)
      }else{
        main_display <- paste0(main_display, ", ", as.character(selected_case$province))
      }
    }
    
    if(is.na(selected_case$country) == FALSE){
      if(length(main_display) == 0){
        main_display <- as.character(selected_case$country)
      }else{
        main_display <- paste0(main_display, ", ", as.character(selected_case$country))
      }
    }
    
    if(length(main_display) == 0){
      main_display <- "Missing Data"
    }
  
    content <- as.character(tagList(
      tags$h4(main_display),
      tags$strong(HTML(sprintf("%s %s",
                               "Symptom Onset Date:", as.character(selected_case$date_onset_symptoms
      )))), tags$br(),
      sprintf("Symptoms: %s", as.character(selected_case$symptoms)), tags$br(),
      sprintf("Hospitalization Date: %s", as.character(selected_case$date_admission_hospital)), tags$br(),
      sprintf("Age: %s", as.character(selected_case$age))
    ))
    leafletProxy("map") %>% addPopups(lng, lat, content, layerId = case_id)
  }
  

  #when map is clicked, show a popup with facility info
  observe({
    event <- input$map_marker_click
    if(is.null(event)){
      return()
    }
      
    leafletProxy("map") %>% clearPopups()
    
    isolate({
      showCasePopup(event$id, event$lat, event$lng)
    })
  
  })
  
  #update filtered case number
  output$total_cases <- reactive({
    filter_data <- make_filter_data()
    
    if(input$confirmed == "Yes"){
      confirmed <- "Confirmed "
    }else{
      confirmed <- " "
    }
    
    if(is.null(x = input$wuhan_resident) == TRUE & is.null(x = input$travel_history_location) == TRUE & is.null(x = input$country) == TRUE){
      paste0(prettyNum(nrow(filter_data), big.mark=",", scientific=FALSE), " Total ", confirmed, "Cases")
    }else{
      paste0(prettyNum(nrow(filter_data), big.mark=",", scientific=FALSE), " ", confirmed, "Filtered Cases")
    }
  })
  
  #reset map
  observeEvent(input$reset_edges, {
    updateSelectInput(session, "wuhan_resident", choices = unique(full_data$lives_in_Wuhan))
    updateSelectInput(session, "travel_history_location", choices = unique(full_data$travel_history_location))
    updateSelectInput(session, "country", choices =  unique(full_data$country))
    updateSelectInput(session, "confirmed", selected = "No")
  })
  ###############
  #Data Explorer#
  ###############
  
  #clickable data table
  observe({
    if (is.null(input$goto))
      return()
    isolate({
      map <- leafletProxy("map")
      leafletProxy("map") %>% clearPopups()
      dist <- 0.5
      name <- input$goto$name
      lat <- input$goto$lat
      lng <- input$goto$lng
      if(is.numeric(lat) == TRUE & is.numeric(lng) == TRUE){
        showCasePopup(name, lat, lng)
        map %>% fitBounds(lng - dist, lat - dist, lng + dist, lat + dist)
      }
    })
  })
  
  #data table for data page, filters come from map page
  output$wuhan_table <- DT::renderDataTable({
    df <- make_filter_data()
    
    df <- df %>%
      mutate(Action = paste('<a class="go-map" href="" data-lat="', latitude, '" data-long="', longitude, '" data-name="', ID, '"><i class="fa fa-crosshairs"></i></a>', sep=""))
    
    action_loc <- which(colnames(df) == "Action")
    colnames(df)[action_loc] <- "Click for Map View"
    
    df <- data.frame(df[,action_loc], df[,-action_loc])
    
    include_cols <- which(colnames(df) %in% c("Click.for.Map.View", cols_to_use))
    df <- df[,include_cols]
    
    action <- DT::dataTableAjax(session, df, outputId = "wuhan_table")
    DT::datatable(df, options = list(ajax = list(url = action)), escape = FALSE)
  })
  
  output$news_table <- DT::renderDataTable({
    df <- make_filter_data()
    if(nrow(df) == 0){
      data.out <- df[,1:2]
    }else{
      short_url <- unlist(lapply(strsplit(split = "[/]", x = df$source), function(x) unlist(x)[3]))
      by_tab <- by(data = short_url, INDICES = df$country, FUN = unique)
      len_country <- unlist(lapply(by_tab, length))
      by_df <- array(by_tab, dim(by_tab), dimnames(by_tab))
      data.out <- data.frame(rep(names(len_country), times = len_country), as.character(unlist(by_tab)))
    }

    colnames(data.out) <- c("Country", "News Sources")
    data.out <- na.omit(data.out)
    
    DT::datatable(data.out)
  })
}