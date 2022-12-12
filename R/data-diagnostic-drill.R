# @file data-diagnostic-drill.R
#
# Copyright 2022 Observational Health Data Sciences and Informatics
#
# This file is part of OhdsiShinyModules
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


#' The module viewer for exploring data-diagnostic results in more detail
#'
#' @details
#' The user specifies the id for the module
#'
#' @param id  the unique reference id for the module
#' 
#' @return
#' The user interface to the summary module
#'
#' @export
dataDiagnosticDrillViewer <- function(id) {
  ns <- shiny::NS(id)
  
  #shiny::div(
  shiny::fluidPage(
    shiny::column(
      width = 2,
      shiny::uiOutput(ns('dataDiagnosticInputs'))
    ),
    shiny::column(
      width = 10,
      reactable::reactableOutput(ns('drugStudyFailSummaryTable'), width = '100%')
    )
  )
  
}

#' The module server for exploring prediction summary results 
#'
#' @details
#' The user specifies the id for the module
#'
#' @param id  the unique reference id for the module
#' @param con the connection to the prediction result database
#' @param mySchema the database schema for the model results
#' @param targetDialect the database management system for the model results
#' @param myTableAppend a string that appends the tables in the result schema
#' 
#' @return
#' The server to the summary module
#'
#' @export
dataDiagnosticDrillServer <- function(
    id, 
    con,
    mySchema,
    targetDialect,
    myTableAppend
) {
  shiny::moduleServer(
    id,
    function(input, output, session) {
    
      analyses <- getAnalysesDataDiagnostics(
        con = con, 
        mySchema = mySchema, 
        targetDialect = targetDialect, 
        myTableAppend = myTableAppend
      )
      databases <- getDbDataDiagnostics(
        con = con, 
        mySchema = mySchema, 
        targetDialect = targetDialect, 
        myTableAppend = myTableAppend
      )

      output$dataDiagnosticInputs <- shiny::renderUI({  
        
        shiny::tagList(
          shiny::selectInput(
            inputId = session$ns("analysisSelected"), 
            label = shiny::h4("Analysis:"), 
            choices =  analyses
          ),
          
          shiny::checkboxGroupInput(
            inputId = session$ns("databasesSelected"), 
            label = shiny::h4("Databases:"), 
            choiceNames =  databases[[1]],
            choiceValues  =  databases[[1]],
            selected = databases[[1]],
            inline = FALSE,
            width = NULL
          )
        )
        
      })

      # inital table
      resultTable <- shiny::reactiveVal(
        value = getDrugStudyFail(
        con = con, 
        mySchema = mySchema, 
        targetDialect = targetDialect, 
        myTableAppend = myTableAppend,
        analysis = analyses[[1]]
      ))
      
      shiny::observeEvent(input$analysisSelected, {
        
        if(!is.null(input$analysisSelected)){
          
          resultTableTemp <- getDrugStudyFail(
            con = con, 
            mySchema = mySchema, 
            targetDialect = targetDialect, 
            myTableAppend = myTableAppend,
            analysis = input$analysisSelected
          )
          resultTable(resultTableTemp)
          
        }
      }) # end observe event analysis
      
    
      output$drugStudyFailSummaryTable <- reactable::renderReactable({
        
        if(!is.null(resultTable())){
          
          
          cinds <- ! (colnames(resultTable()) %in% c('databaseId', 'minSampleSize', 'maxSampleSize',"analysisId", "analysisName"))
          
          columnFormat2 <- lapply(
            X = 1:ncol(resultTable()[, cinds]), 
            
            FUN = function(x){
              return(
                reactable::colDef(
                  style = function(value) {
                    if (value > 0) {
                      color <- '#e00000'
                    } else {
                      color <- "#008000"
                    }
                    list(color = color, fontWeight = "bold")
                  }
                )
              )
            }
            
          )
          names(columnFormat2) <- colnames(resultTable()[, cinds])
           
            reactable::reactable(
              data = resultTable() %>% 
                dplyr::select(-c("analysisId", "analysisName")) %>%
                dplyr::filter(.data$databaseId %in% input$databasesSelected) %>%
                dplyr::mutate(view  = '') %>%
                dplyr::relocate("view", .before = 'databaseId'),
              defaultPageSize = 20,
              searchable = TRUE,
              columns = c(
                list(
                  view = reactable::colDef(
                  name = "",
                  sortable = FALSE,
                  cell = function() htmltools::tags$button("View")
                )), 
                columnFormat2
              ),
              onClick = reactable::JS(paste0("function(rowInfo, column) {
    // Only handle click events on the 'details' column
    if (column.id !== 'view') {
      return
    }
    // Send the click event to Shiny, which will be available in input$show_details
    // Note that the row index starts at 0 in JavaScript, so we add 1
      Shiny.setInputValue('",session$ns('show_details'),"', { index: rowInfo.index + 1 }, { priority: 'event' })
  }")
              )
            )

        }
        
      }) # end reactable
      
      
      #  Now add module to show details: input$show_details
      shiny::observeEvent(input$show_details, {
        
        database <- resultTable() %>% 
          dplyr::select("databaseId") %>%
          dplyr::filter(.data$databaseId %in% input$databasesSelected)
        
        databaseId <- database$databaseId[input$show_details$index]
        analysisId <- input$analysisSelected
        
        output$modaltable <- reactable::renderReactable({
          reactable::reactable(
            data = getDrillDown(
              con = con, 
              mySchema = mySchema, 
              targetDialect = targetDialect, 
              myTableAppend = myTableAppend,
              analysisId = analysisId, 
              databaseId = databaseId
            )
          )
        }
        )

        shiny::showModal(
          shiny::modalDialog(
            title = "Details",
            paste0("For database: ", databaseId, " and analysisId ", analysisId),

            reactable::reactableOutput(session$ns("modaltable")),
        
            easyClose = TRUE,
            footer = NULL,
            size = "l"
            
          )
        )
           
        
      })
      
      
    }
  )
}

getDrillDown <- function(
  con = con, 
  mySchema = mySchema, 
  targetDialect = targetDialect, 
  myTableAppend = myTableAppend,
  analysisId = analysisId, 
  databaseId = databaseId
){
  
  sql <- "SELECT *FROM @my_schema.@my_table_appenddata_diagnostics_output
  WHERE analysis_id = @analysis_id and database_id = '@database_id';"
  
  sql <- SqlRender::render(
    sql = sql, 
    my_schema = mySchema,
    my_table_append = myTableAppend,
    analysis_id = analysisId,
    database_id = databaseId
  )
  
  sql <- SqlRender::translate(sql = sql, targetDialect =  targetDialect)
  
  result <- DatabaseConnector::dbGetQuery(conn =  con, statement = sql) 
  colnames(result) <- SqlRender::snakeCaseToCamelCase(colnames(result))
  
  result <- result %>%
    dplyr::select(-c("databaseId", "analysisId", "analysisName"))
  
  return(result)
}


getAnalysesDataDiagnostics <- function(
  con = con, 
  mySchema = mySchema, 
  targetDialect = targetDialect, 
  myTableAppend = myTableAppend
){
  
  print('Getting Analyses')
  
  sql <- "SELECT distinct analysis_id, analysis_name FROM @my_schema.@my_table_appenddata_diagnostics_summary;"
  
  sql <- SqlRender::render(
    sql = sql, 
    my_schema = mySchema,
    my_table_append = myTableAppend
  )
  
  sql <- SqlRender::translate(sql = sql, targetDialect =  targetDialect)
  
  analysisNames <- DatabaseConnector::dbGetQuery(conn =  con, statement = sql) 
  colnames(analysisNames) <- SqlRender::snakeCaseToCamelCase(colnames(analysisNames))
  
  result <- as.list(analysisNames$analysisId)
  names(result) <- analysisNames$analysisName
  
  print('Got Analyses')
  
  return(result)
  
}

getDbDataDiagnostics <- function(
  con = con, 
  mySchema = mySchema, 
  targetDialect = targetDialect, 
  myTableAppend = myTableAppend
){
  
  sql <- "SELECT distinct database_id FROM @my_schema.@my_table_appenddata_diagnostics_summary;"
  
  sql <- SqlRender::render(
    sql = sql, 
    my_schema = mySchema,
    my_table_append = myTableAppend
  )
  
  sql <- SqlRender::translate(sql = sql, targetDialect =  targetDialect)
  
  dbNames <- DatabaseConnector::dbGetQuery(conn =  con, statement = sql) 
  colnames(dbNames) <- SqlRender::snakeCaseToCamelCase(colnames(dbNames))
  
  result <- list(dbNames$databaseId)
  
  return(result)
  
}

getDrugStudyFail <- function(
    con, 
    mySchema, 
    targetDialect, 
    myTableAppend = '',
    analysis = NULL
){
  
  if(is.null(analysis)){
    return(NULL)
  }
  
  shiny::withProgress(message = 'Extracting data diagnostic summary', value = 0, {
    
    shiny::incProgress(1/3, detail = paste("Extracting data"))
    
    sql <- "SELECT * FROM @my_schema.@my_table_appenddata_diagnostics_summary
  WHERE analysis_id = @analysis;"
    
    sql <- SqlRender::render(
      sql = sql, 
      my_schema = mySchema,
      my_table_append = myTableAppend,
      analysis = analysis
    )
    
    sql <- SqlRender::translate(sql = sql, targetDialect =  targetDialect)
    
    summaryTable <- DatabaseConnector::dbGetQuery(conn =  con, statement = sql) 
    
    shiny::incProgress(2/3, detail = paste("Data extracted"))
    
    colnames(summaryTable) <- SqlRender::snakeCaseToCamelCase(colnames(summaryTable))
    
    # hide analysisId and analysisName
    
    shiny::incProgress(3/3, detail = paste("Finished"))
    
    ParallelLogger::logInfo("Got database diagnostic fail summary")
    
  })
  
  return(summaryTable)  
}