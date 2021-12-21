library(dplyr)
library(data.table)
library(progress)
library(data.table)
library(stringr)

calculate_jaccard <- function(from, to)
{
  # this works by ignoring the environmental variable (after the | in the string)
  substr_from = strsplit(from,"\\|")[[1]][1]
  substr_to = strsplit(to,"\\|")[[1]][1]
  
  vec_from = strsplit(substr_from, "\\*")[[1]]
  vec_to = strsplit(substr_to, "\\*")[[1]]
  
  index_jaccard = length(intersect(vec_from, vec_to)) / length(union(vec_from, vec_to))
  
  return(index_jaccard)
}

calculate_richness <- function(state)
{
  substr_state = strsplit(state,"\\|")[[1]][1]
  vec_state = strsplit(substr_state, "\\*")[[1]]
  
  return(length(vec_state))
}

assign_params_to_state <- function(data, params_A, params_r)
{
  # hack to go faster (less data passed)
  data_ss = data %>% select(from, to, name)
  
  # apply states and environments to all rows (this is the 'from')
  state_env_from = rbindlist(lapply(data_ss$from, get_state_env))
  names(state_env_from) = paste(names(state_env_from),"from",sep="_")
  state_env_to = rbindlist(lapply(data_ss$to, get_state_env))
  names(state_env_to) = paste(names(state_env_to),"to",sep="_")
  # put it all together
  data_ss_state_env = cbind(name=as.character(data_ss$name), state_env_from, state_env_to)
  
  # make progress bar
  pb <- progress_bar$new(total = nrow(data_ss), format = "[:bar] :current :total")
  # assign values for each state
  result_final_raw = lapply(1:nrow(data_ss), function(i)
  {
    pb$tick()
    # FROM
    species_this_from = as.numeric(strsplit(data_ss_state_env$state_from[i],split="*",fixed=TRUE)[[1]])
    env_this_from = as.numeric(data_ss_state_env$env_from[i])
    name_this = data_ss_state_env$name[i]
    
    # get appropriate A value at the right environment
    params_A_this_from = params_A[[env_this_from]][species_this_from, species_this_from]
    
    # get appropriate r value at the right environment
    params_r_this_from = params_r[[env_this_from]][species_this_from]
    
    # TO
    species_this_to = as.numeric(strsplit(data_ss_state_env$state_to[i],split="*",fixed=TRUE)[[1]])
    env_this_to = as.numeric(data_ss_state_env$env_to[i])
    name_this = data_ss_state_env$name[i]
    
    # get appropriate A value at the right environment
    params_A_this_to = params_A[[env_this_to]][species_this_to, species_this_to]
    
    # get appropriate r value at the right environment
    params_r_this_to = params_r[[env_this_to]][species_this_to]
    
    result = data.frame(A_from_mean = mean(as.numeric(as.matrix(params_A_this_from)), na.rm=T),
                        A_from_sd = sd(as.numeric(as.matrix(params_A_this_from)), na.rm=T),
                        r_from_mean = mean(as.numeric(params_r_this_from), na.rm=T),
                        r_from_sd = sd(as.numeric(params_r_this_from), na.rm=T),
                        A_to_mean = mean(as.numeric(as.matrix(params_A_this_to)), na.rm=T),
                        A_to_sd = sd(as.numeric(as.matrix(params_A_this_to)), na.rm=T),
                        r_to_mean = mean(as.numeric(params_r_this_to), na.rm=T),
                        r_to_sd = sd(as.numeric(params_r_this_to), na.rm=T)
    )
    return(result)
  })
  
  result_final = rbindlist(result_final_raw)
  
  return(cbind(data, result_final))
}

get_state_env <- function(pp)
{
  pp = gsub("[\\(\\)]","",pp)
  state = strsplit(pp, "\\|")[[1]][1]
  env = strsplit(pp, "\\|")[[1]][2]
  
  return(data.frame(state=state,env=env))
}

get_path_df <- function(path_this)
{
  transitions = c(strsplit(gsub("[\\(\\)\\|\\*01234567890]","",path_this),"")[[1]],NA)
  path_parts = strsplit(path_this,"[-\\+\\=\\>]")[[1]] # the regex allows for - (deletion), + (addition), = (environment change), > (natural) transitions
  path_df = rbindlist(lapply(path_parts, get_state_env))
  
  path_df$transition = transitions  
  path_df$richness = sapply(strsplit(path_df$state,"\\*"),length)
  path_df$id = 1:nrow(path_df)
  
  path_df = path_df %>% select(id, state, env, transition, richness)
  
  return(path_df)
}


parse_simulated_parameters <- function(fn, n_sp)
{
  lines = readLines(fn)
  
  line_a = which(lines=="A matrices:")
  line_r = which(lines=="r vectors:")
  
  strings_A = strsplit(gsub("\n","",paste(gsub(sprintf("%d×%d Matrix{Float64}:",n_sp,n_sp),"~",gsub("\\(T = [0-9]\\)","",lines[(line_a+3):(line_r-2)]),fixed=TRUE),collapse="\n"),fixed=TRUE),split="~",fixed=TRUE)[[1]]
  list_A = lapply(strsplit(strings_A,split=" +"), function(x) {
    result = x %>% as.numeric %>% na.omit %>% matrix(nrow=n_sp,ncol=n_sp)
    return(result)
  })
  
  strings_r = strsplit(gsub("\n","",paste(gsub(sprintf("%d-element Vector{Float64}:",n_sp),"~",gsub("\\(T = [0-9]\\)","",lines[(line_r+3):length(lines)]),fixed=TRUE),collapse="\n"),fixed=TRUE),split="~",fixed=TRUE)[[1]]
  list_r = lapply(strsplit(strings_r,split=" +"), function(x) { 
    result = x %>% as.numeric %>% na.omit %>% t %>% as.data.frame
    names(result) = 1:length(result)
    return(result)
  })
  
  return(list(params_A = list_A, params_r = list_r))
}


prep_data <- function(df, params_A, params_r)
{
  df_processed = df %>%
    mutate(proportional_cost_improvement = (net_cost - net_cost_astar) / net_cost)
  
  message('calculating Jaccard')
  df_processed$jaccard_vals = sapply(1:nrow(df_processed), function(i) {calculate_jaccard(df_processed$from[i], df_processed$to[i])})
  message('calculating richness from')
  df_processed$richness_from = sapply(1:nrow(df_processed), function(i) {calculate_richness(df_processed$from[i])})
  message('calculating richness to')
  df_processed$richness_to = sapply(1:nrow(df_processed), function(i) {calculate_richness(df_processed$to[i])})
  
  # convert integers to factors for random forest
  df_processed = df_processed %>% 
    mutate(name=factor(name))
  
  # for rare cases where we go from 0 to 0 richness...
  df_processed$jaccard_vals[is.nan(df_processed$jaccard_vals)] <- 1
  
  # assign parameters
  message('assigning mean/sd A and r parameters')
  df_processed = assign_params_to_state(df_processed, params_A, params_r)
  
  return(df_processed)
}

process_dataset <- function(fn_astar, fn_A, fn_r, name, params_A=NULL, params_r=NULL)
{
  # send out progress update
  message(name)
  
  # load in parameters
  data = read.csv(fn_astar)
  if (!is.null(fn_r))
  {
    params_r = lapply(fn_r, read.csv, check.names=FALSE)
  } else
  {
    params_r = params_r
  }
  
  if (!is.null(fn_A))
  {
    params_A = lapply(fn_A, read.csv, check.names=FALSE)
  } else
  {
    params_A = params_A
  }
  taxa = names(params_r[[1]])
  
  data$name = name
  data$n = ncol(params_r[[1]])
  data$m = length(params_r)
  data$num_transitions_natural = NA
  data$num_transitions_environment = NA
  data$num_transitions_addition = NA
  data$num_transitions_removal = NA
  
  message('counting transitions')
  pb <- progress_bar$new(total = nrow(data), format = "[:bar] :current :total")
  for (i in 1:nrow(data))
  {
    pb$tick()
    data$num_transitions_natural[i] = str_count(data$path_astar[i],fixed(">"))
    data$num_transitions_environment[i] = str_count(data$path_astar[i],fixed("="))
    data$num_transitions_addition[i] = str_count(data$path_astar[i],fixed("+"))
    data$num_transitions_removal[i] = str_count(data$path_astar[i],fixed("-"))
  }
  pb$terminate()
  
  # do additional prep work
  data = prep_data(data, params_A, params_r)
  
  return(list(data=data,
              params_r=params_r,
              params_A=params_A, 
              taxa=taxa))
}







# LOAD IN DATASETS
data_mouse_gut = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/experimental/astar_results_Bucci_Mon_29_Nov_2021_17_18.csv',
                                 fn_A = '../CoexistenceControl-Private/data/dataset/bucci/a_matrix.csv',
                                 fn_r = '../CoexistenceControl-Private/data/dataset/bucci/r_vector.csv',
                                 name = 'Mouse gut')

data_human_gut = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/experimental/astar_results_Venturelli_Mon_29_Nov_2021_17_14.csv',
                                 fn_A = '../CoexistenceControl-Private/data/dataset/venturelli/a_matrix.csv',
                                 fn_r = '../CoexistenceControl-Private/data/dataset/venturelli/r_vector.csv',
                                 name = 'Human gut')

data_ciliate_small = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/experimental/astar_results_Maynard15-19-23_Mon_29_Nov_2021_17_19.csv',
                                 fn_A = c('../CoexistenceControl-Private/data/dataset/maynard/15/a_matrix.csv','../CoexistenceControl-Private/data/dataset/maynard/19/a_matrix.csv','../CoexistenceControl-Private/data/dataset/maynard/23/a_matrix.csv'),
                                 fn_r = c('../CoexistenceControl-Private/data/dataset/maynard/15/r_vector.csv','../CoexistenceControl-Private/data/dataset/maynard/19/r_vector.csv','../CoexistenceControl-Private/data/dataset/maynard/23/r_vector.csv'),
                                 name = 'Ciliate (small)')

data_ciliate_large = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/experimental/astar_results_Maynard15-17-19-21-23_Mon_29_Nov_2021_17_20.csv',
                                     fn_A = c('../CoexistenceControl-Private/data/dataset/maynard/15/a_matrix.csv','../CoexistenceControl-Private/data/dataset/maynard/17/a_matrix.csv','../CoexistenceControl-Private/data/dataset/maynard/19/a_matrix.csv','../CoexistenceControl-Private/data/dataset/maynard/21/a_matrix.csv','../CoexistenceControl-Private/data/dataset/maynard/23/a_matrix.csv'),
                                     fn_r = c('../CoexistenceControl-Private/data/dataset/maynard/15/r_vector.csv','../CoexistenceControl-Private/data/dataset/maynard/17/r_vector.csv','../CoexistenceControl-Private/data/dataset/maynard/19/r_vector.csv','../CoexistenceControl-Private/data/dataset/maynard/21/r_vector.csv','../CoexistenceControl-Private/data/dataset/maynard/23/r_vector.csv'),
                                     name = 'Ciliate (large)')

data_protist = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/experimental/astar_results_Carrara_Mon_29_Nov_2021_17_19.csv',
                                 fn_A = '../CoexistenceControl-Private/data/dataset/carrara/a_matrix.csv',
                                 fn_r = '../CoexistenceControl-Private/data/dataset/carrara/r_vector.csv',
                                 name = 'Protist')

data_simulated_n5_t3 = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/synthetic/n5_t3/astar_results_synthetic_n5_t3_i1_Wed_1_Dec_2021_03_06.csv',
                                       fn_A = NULL,
                                       params_A = parse_simulated_parameters('../CoexistenceControl-Private/data/results/synthetic/n5_t3/astar_results_synthetic_n5_t3_i1_Wed_1_Dec_2021_03_06.txt', n_sp=5)$params_A,
                                       fn_r = NULL,
                                       params_r = parse_simulated_parameters('../CoexistenceControl-Private/data/results/synthetic/n5_t3/astar_results_synthetic_n5_t3_i1_Wed_1_Dec_2021_03_06.txt', n_sp=5)$params_r,
                                       name = 'Simulated n5t3')

data_simulated_n10_t1 = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/synthetic/n10_t1/astar_results_synthetic_n10_t1_i1_Wed_1_Dec_2021_03_07.csv',
                                       fn_A = NULL,
                                       params_A = parse_simulated_parameters('../CoexistenceControl-Private/data/results/synthetic/n10_t1/astar_results_synthetic_n10_t1_i1_Wed_1_Dec_2021_03_07.txt', n_sp=10)$params_A,
                                       fn_r = NULL,
                                       params_r = parse_simulated_parameters('../CoexistenceControl-Private/data/results/synthetic/n10_t1/astar_results_synthetic_n10_t1_i1_Wed_1_Dec_2021_03_07.txt', n_sp=10)$params_r,
                                       name = 'Simulated n10t1')

data_simulated_n15_t1 = process_dataset(fn_astar = '../CoexistenceControl-Private/data/results/synthetic/n15_t1/astar_results_synthetic_n15_t1_i1_Wed_1_Dec_2021_11_19.csv',
                                        fn_A = NULL,
                                        params_A = parse_simulated_parameters('../CoexistenceControl-Private/data/results/synthetic/n15_t1/astar_results_synthetic_n15_t1_i1_Wed_1_Dec_2021_11_19.txt', n_sp=15)$params_A,
                                        fn_r = NULL,
                                        params_r = parse_simulated_parameters('../CoexistenceControl-Private/data/results/synthetic/n15_t1/astar_results_synthetic_n15_t1_i1_Wed_1_Dec_2021_11_19.txt', n_sp=15)$params_r,
                                        name = 'Simulated n15t1')

# put datasets together
data_processed = rbind(data_mouse_gut$data, 
                                           data_human_gut$data, 
                                           data_ciliate_small$data, 
                                           data_ciliate_large$data, 
                                           data_protist$data,
                                           data_simulated_n5_t3$data,
                                           data_simulated_n10_t1$data,
                                           data_simulated_n15_t1$data
  )

# also make a list by name of datasets
datasets_all = list(
  `Ciliate (large)`=data_ciliate_large,
  `Ciliate (small)`=data_ciliate_small,
  `Human gut`=data_human_gut,
  `Mouse gut`=data_mouse_gut,
  `Protist`=data_protist,
  `Simulated n10t1`=data_simulated_n10_t1,
  `Simulated n15t1`=data_simulated_n15_t1,
  `Simulated n5t3`=data_simulated_n5_t3
)

# make table of all the species
make_taxa_df <- function(dataset)
{
  data.frame(taxon=names(dataset$params_r[[1]]),id=1:length(dataset$params_r[[1]]),name=dataset$data$name[1])
}
df_taxa = rbindlist(lapply(list(data_mouse_gut, 
                                data_human_gut, 
                                data_ciliate_small, 
                                data_ciliate_large, 
                                data_protist,
                                data_simulated_n5_t3,
                                data_simulated_n10_t1,
                                data_simulated_n15_t1), make_taxa_df))
warning('need to shorten names')


# additional nomenclature
edge_labels_long = c(`>`='Natural',`-`='Species removal',`+`='Species addition',`=`='Environment change')


# save the results
save.image(file='prepared datasets.Rdata')