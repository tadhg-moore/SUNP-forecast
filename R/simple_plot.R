simple_plot <- function(forecast_file_name,
                        output_file_name,
                        qaqc_data_directory,
                        focal_depths_plotting,
                        highlight_date = NA){
  
####
pdf_file_name <- paste0(tools::file_path_sans_ext(output_file_name),".pdf")
csv_file_name <- paste0(tools::file_path_sans_ext(output_file_name),".csv")


output <- FLAREr::combine_forecast_observations(file_name = forecast_file_name,
                                                qaqc_data_directory = qaqc_data_directory,
                                                extra_historical_days = 0,
                                                ncore = 1)
obs <- output$obs
full_time_extended <- output$full_time_extended
diagnostic_list <- output$diagnostic_list
state_list <- output$state_list
forecast <- output$forecast
par_list <- output$par_list
obs_list <- output$obs_list
state_names <- output$state_names
par_names <- output$par_names
diagnostics_names <- output$diagnostics_names
full_time <- output$full_time
obs_long <- output$obs_long
depths <- output$depths
obs_names <- output$obs_names


if(length(which(forecast == 1)) > 0){
  forecast_index <- which(forecast == 1)[1]
}else{
  forecast_index <- 0
}

#focal_depths_plotting <- depths


if(length(focal_depths_plotting) < 4){
  plot_height <- 3
}else{
  plot_height <- 8
}
pdf(pdf_file_name,width = 11, height = plot_height)

evaluation_df <- NULL

for(i in 1:length(state_names)){
  
  curr_var <- state_list[[i]]
  message(state_names[i])
  
  
  mean_var <- array(NA, dim = c(length(depths), length(full_time)))
  upper_var <- array(NA, dim = c(length(depths), length(full_time)))
  lower_var <- array(NA,dim = c(length(depths), length(full_time)))
  sd_var <- array(NA,dim = c(length(depths), length(full_time)))
  for(j in 1:length(full_time)){
    for(ii in 1:length(depths)){
      mean_var[ii, j] <- mean(curr_var[j,ii , ], na.rm = TRUE)
      sd_var[ii, j] <- sd(curr_var[j,ii , ], na.rm = TRUE)
      upper_var[ii, j] <- quantile(curr_var[j,ii , ], 0.1, na.rm = TRUE)
      lower_var[ii, j] <- quantile(curr_var[j,ii , ], 0.9, na.rm = TRUE)
    }
  }
  
  date <- c()
  for(j in 1:length(full_time)){
    date <- c(date, rep(full_time[j], length(depths)))
  }
  
  if(state_names[i] %in% unlist(obs_names)){
    obs_index <- which(obs_names == state_names[i])
    obs_curr <- as.numeric(c(t(obs[, ,obs_index])))
  }else{
    obs_curr <- as.numeric(rep(NA, length(date)))
  }
  
  if(forecast_index > 0){
    forecast_start_day <- full_time[forecast_index-1]
    forecast_start_day_alpha <- 1.0
  }else{
    forecast_start_day <- dplyr::last(full_time)
    forecast_start_day_alpha <- 0.0
  }
  
  curr_tibble <- tibble::tibble(date = lubridate::as_datetime(date),
                                forecast_mean = round(c(mean_var),4),
                                forecast_sd = round(c(sd_var),4),
                                forecast_upper_95 = round(c(upper_var),4),
                                forecast_lower_95 = round(c(lower_var),4),
                                observed = round(obs_curr,4),
                                depth = rep(depths, length(full_time)),
                                state = state_names[i],
                                forecast_start_day = forecast_start_day) %>%
    dplyr::filter(depth %in% focal_depths_plotting)
  
  
  p <- ggplot2::ggplot(curr_tibble, ggplot2::aes(x = date)) +
    ggplot2::facet_wrap(~depth) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = forecast_lower_95, ymax = forecast_upper_95),
                         alpha = 0.70,
                         fill = "gray") +
    ggplot2::geom_line(ggplot2::aes(y = forecast_mean), size = 0.5) +
    ggplot2::geom_vline(xintercept = forecast_start_day,
                        alpha = forecast_start_day_alpha) +
    ggplot2::geom_point(ggplot2::aes(y = observed), size = 0.5, color = "red") +
    ggplot2::theme_light() +
    ggplot2::labs(x = "Date", y = state_names[i], title = paste0(state_names[i], " forecast on ", lubridate::date(forecast_start_day))) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 90, size = 10))
  if(!is.na(highlight_date)){
    p <- p + 
      ggplot2::geom_vline(xintercept = as.POSIXct(highlight_date), col = 'blue')
  }

  print(p)
  
 



dev.off()

}
}
