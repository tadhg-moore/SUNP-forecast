# combine first cycle noaa forecasts as obs


stack_noaa_forecasts <- function(dates, # list of dates you have NOAA GEFS .nc forecasts for 
                                 cycle = '00',
                                 outfile, # file path where you want the output file to go
                                 config # FLARE config list
                                 ){
  
# cf_met_vars <- c("air_temperature",
#                  "surface_downwelling_shortwave_flux_in_air",
#                  "surface_downwelling_longwave_flux_in_air",
#                  "relative_humidity",
#                  "wind_speed",
#                  "precipitation_flux")
# 
  cf_met_vars <- c("air_temperature", "air_pressure", "relative_humidity", "surface_downwelling_longwave_flux_in_air",
                     "surface_downwelling_shortwave_flux_in_air", "precipitation_flux","specific_humidity","wind_speed")
  
  cf_var_units1 <- c("K", "Pa", "1", "Wm-2", "Wm-2", "kgm-2s-1", "1", "ms-1")  #Negative numbers indicate negative exponents
  
  
# glm_met_vars <- c("AirTemp",
#                   "ShortWave",
#                   "LongWave",
#                   "RelHum",
#                   "WindSpeed",
#                   "Rain")
# 
  # .nc file metadata info
  model_name <- "observed-met-noaa"
  site <- config$location$site_id
  lat <- config$location$latitude
  lon <- config$location$longitude
  cf_units <- cf_var_units1
  identifier <- paste(model_name, site,sep="_")
  fname <- paste0(identifier,".nc")
  output_file <- file.path(outfile, fname)
  
  # set up dataframe for outfile
  noaa_obs_out <- data.frame(matrix(ncol=length(cf_met_vars)), nrow = 0)
  colnames(noaa_obs_out) <- c('time', cf_met_vars)
  noaa_obs_out$time <- as.POSIXct(noaa_obs_out$time)
  
  # loop through each date of forecasts and extract the first day, stack together to create a continuous dataset of day 1 forecasts
  for(k in 1:length(dates)){
    
    forecast_dir <- file.path(config$file_path$noaa_directory, config$met$forecast_met_model, config$location$site_id, dates[k], cycle)
    
    if(!is.null(forecast_dir)){
      
      forecast_files <- list.files(forecast_dir, pattern = ".nc", full.names = TRUE)
      nfiles <- length(forecast_files)
      
    }
    
    if(length(forecast_files) < 1){
      noaa_obs_out <- na.omit(noaa_obs_out)
      #write.csv(noaa_obs_out, paste0(outfile, '/NOAA_GEFS_mean_ens_', dates[1], '-', dates[k-1], '.csv'), row.names = FALSE)
      # write to nc
      start_time <- min(noaa_obs_out$time)
      end_time <- max(noaa_obs_out$time)
      
      data <- noaa_obs_out %>%
        dplyr::select(-time)
      
      diff_time <- as.numeric(difftime(noaa_obs_out$time, noaa_obs_out$time[1], units = "hours"))
      
      cf_var_names <- names(data)
      
      time_dim <- ncdf4::ncdim_def(name="time",
                                   units = paste("hours since", format(start_time, "%Y-%m-%d %H:%M")),
                                   diff_time, #GEFS forecast starts 5 hours from start time
                                   create_dimvar = TRUE)
      lat_dim <- ncdf4::ncdim_def("latitude", "degree_north", lat, create_dimvar = TRUE)
      lon_dim <- ncdf4::ncdim_def("longitude", "degree_east", lon, create_dimvar = TRUE)
      
      dimensions_list <- list(time_dim, lat_dim, lon_dim)
      
      nc_var_list <- list()
      for (i in 1:length(cf_var_names)) { #Each ensemble member will have data on each variable stored in their respective file.
        nc_var_list[[i]] <- ncdf4::ncvar_def(cf_var_names[i], cf_units[i], dimensions_list, missval=NaN)
      }
      
      nc_flptr <- ncdf4::nc_create(output_file, nc_var_list, verbose = FALSE, )
      
      #For each variable associated with that ensemble
      for (j in 1:ncol(data)) {
        # "j" is the variable number.  "i" is the ensemble number. Remember that each row represents an ensemble
        ncdf4::ncvar_put(nc_flptr, nc_var_list[[j]], unlist(data[,j]))
      }
      ncdf4::nc_close(nc_flptr)  #Write to the disk/storage
    }
    
      daily_noaa <- data.frame(matrix(ncol = length(cf_met_vars) + 2, nrow = 0))
      colnames(daily_noaa) <- c('time', cf_met_vars, 'ens')
      
      for(j in 1:nfiles){
        
        if(!is.null(forecast_dir) & config$met$use_forecasted_met) {
          
          ens <- dplyr::last(unlist(stringr::str_split(basename(forecast_files[j]),"_")))
          ens <- stringr::str_sub(ens,1,5)
          noaa_met_nc <- ncdf4::nc_open(forecast_files[j])
          noaa_met_time <- ncdf4::ncvar_get(noaa_met_nc, "time")
          origin <- stringr::str_sub(ncdf4::ncatt_get(noaa_met_nc, "time")$units, 13, 28)
          origin <- lubridate::ymd_hm(origin)
          noaa_met_time <- origin + lubridate::hours(noaa_met_time)
          noaa_met <- tibble::tibble(time = noaa_met_time)
          
          for(i in 1:length(cf_met_vars)){
            noaa_met <- cbind(noaa_met, ncdf4::ncvar_get(noaa_met_nc, cf_met_vars[i]))
          }
          
          ncdf4::nc_close(noaa_met_nc)
          names(noaa_met) <- c("time", cf_met_vars) # glm_met_vars
          
          noaa_met <- noaa_met %>%
            dplyr::mutate(ens = j) %>% 
            dplyr::mutate(date = lubridate::as_date(time)) %>% 
            dplyr::filter(date %in% dates[k]) %>% 
            select(-date)
          
          daily_noaa <- rbind(noaa_met, daily_noaa)
        }
      }
      
      daily_noaa_mean <- daily_noaa %>% 
        dplyr::group_by(time) %>% 
        dplyr::mutate(air_temperature = mean(air_temperature),
                      air_pressure = mean(air_pressure),
                      relative_humidity = mean(relative_humidity),
                      surface_downwelling_longwave_flux_in_air = mean(surface_downwelling_longwave_flux_in_air),
                      surface_downwelling_shortwave_flux_in_air = mean(surface_downwelling_shortwave_flux_in_air),
                      precipitation_flux = mean(precipitation_flux),
                      specific_humidity = mean(specific_humidity),
                      wind_speed = mean(wind_speed)) %>% 
        distinct(time, .keep_all = TRUE) %>% 
        select(-ens)
      
      noaa_obs_out <- rbind(noaa_obs_out, daily_noaa_mean)
      
    }
  noaa_obs_out <- na.omit(noaa_obs_out)
  #write.csv(noaa_obs_out, paste0(outfile, '/NOAA_GEFS_mean_ens_', dates[1], '-', dates[k-1], '.csv'), row.names = FALSE)
  start_time <- min(noaa_obs_out$time)
  end_time <- max(noaa_obs_out$time)
  
  data <- noaa_obs_out %>%
    dplyr::select(-time)
  
  diff_time <- as.numeric(difftime(noaa_obs_out$time, noaa_obs_out$time[1], units = "hours"))
  
  cf_var_names <- names(data)
  
  time_dim <- ncdf4::ncdim_def(name="time",
                               units = paste("hours since", format(start_time, "%Y-%m-%d %H:%M")),
                               diff_time, #GEFS forecast starts 5 hours from start time
                               create_dimvar = TRUE)
  lat_dim <- ncdf4::ncdim_def("latitude", "degree_north", lat, create_dimvar = TRUE)
  lon_dim <- ncdf4::ncdim_def("longitude", "degree_east", lon, create_dimvar = TRUE)
  
  dimensions_list <- list(time_dim, lat_dim, lon_dim)
  
  nc_var_list <- list()
  for (i in 1:length(cf_var_names)) { #Each ensemble member will have data on each variable stored in their respective file.
    nc_var_list[[i]] <- ncdf4::ncvar_def(cf_var_names[i], cf_units[i], dimensions_list, missval=NaN)
  }
  
  nc_flptr <- ncdf4::nc_create(output_file, nc_var_list, verbose = FALSE, )
  
  #For each variable associated with that ensemble
  for (j in 1:ncol(data)) {
    # "j" is the variable number.  "i" is the ensemble number. Remember that each row represents an ensemble
    ncdf4::ncvar_put(nc_flptr, nc_var_list[[j]], unlist(data[,j]))
  }
  
  ncdf4::nc_close(nc_flptr)  #Write to the disk/storage
  
  }


