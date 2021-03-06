PRJROOT =  rprojroot::find_root(criterion=rprojroot::is_git_root)  
source(C("load_packages_set_paths.R"))

all_models = TRUE

source(P("funcoes.R"))

### Set if looking for specific date
#data_date = as.Date("2020-04-02")
data_date = NULL
fix_missing_dates = FALSE
source(C("00-read_process_SIVEP_CSV.R"))
EXPORT = function(...) file.path(CODEROOT, ...)
#probabilidade de hospitalizado ir pra UTI, 

getProbUTI = function(df){
  df.UTI = filter(df, !is.na(UTI) & UTI!=9)
  UTI_table = as.matrix(table(df.UTI$age_class, df.UTI$UTI))
  UTI_data = data.frame(UTIadmissions = UTI_table[,1], trials = rowSums(UTI_table), age_class = age_table$ID)
  
  UTI_prob_model = brm(data = UTI_data, family = binomial,
                       UTIadmissions | trials(trials) ~ 1 + (1|age_class),
                       c(prior("normal(0, 1)", class = "Intercept"),
                         prior("normal(0, 1)", class = "sd")),
                       control = list(adapt_delta = 0.99))
  
  out = coef(UTI_prob_model) %>%
    {inv_logit_scaled(.$age_class)}
  data.frame(out[,,"Intercept"])
}

prob_uti_covid = getProbUTI(covid.dt) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything()) 
prob_uti_srag = getProbUTI(srag.dt) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything()) 

write_csv(prob_uti_covid, EXPORT("prob_UTI_covid"))
write_csv(prob_uti_covid, EXPORT("prob_UTI_srag"))

# probabilidade de morte de hospitalizado comum, e em UTI, 
getProbDeath = function(df, UTI = FALSE){
  if(UTI){
    df.filtered = filter(df, UTI==1, !is.na(evolucao) & evolucao!=9)
  } else{
    df.filtered = filter(df, UTI!=1, !is.na(evolucao) & evolucao!=9)
  }
  case_table = as.matrix(table(df.filtered$age_class, df.filtered$evolucao))
  
  trial_data = data.frame(deaths = 0, trials = 0, age_class = age_table$ID)
  trial_data[match(rownames(case_table), age_table$ID),1] = case_table[,2]
  trial_data[match(rownames(case_table), age_table$ID),2] = rowSums(case_table)
  trial_data$trials[trial_data$trials == 0] = 1 # Adds one trial if none exist
  death_prob_model = brm(data = trial_data, family = binomial,
                         deaths | trials(trials) ~ 1 + (1|age_class),
                         c(prior("normal(0, 1)", class = "Intercept"),
                           prior("normal(0, 1)", class = "sd")),
                         control = list(adapt_delta = 0.99))
  out = coef(death_prob_model) %>%
    {inv_logit_scaled(.$age_class)}
  data.frame(out[,,"Intercept"])
}

if(all_models){
  prob_death_UTI_covid = getProbDeath(covid.dt, UTI = T) %>% 
    mutate(faixas = age_table$faixas) %>% 
    select(faixas, everything())
  prob_death_notUTI_covid = getProbDeath(covid.dt, UTI = F) %>% 
    mutate(faixas = age_table$faixas) %>% 
    select(faixas, everything())
  prob_death_UTI_srag = getProbDeath(srag.dt, UTI = T) %>% 
    mutate(faixas = age_table$faixas) %>% 
    select(faixas, everything())
  prob_death_notUTI_srag = getProbDeath(srag.dt, UTI = F) %>% 
    mutate(faixas = age_table$faixas) %>% 
    select(faixas, everything())
  
  write_csv(prob_death_UTI_covid, EXPORT("prob_death_UTI_covid"))
  write_csv(prob_death_notUTI_covid, EXPORT("prob_death_notUTI_covid"))
  write_csv(prob_death_UTI_srag, EXPORT("prob_death_UTI_srag"))
  write_csv(prob_death_notUTI_srag, EXPORT("prob_death_notUTI_srag"))
  
  probsFits = list(covid = list(uti = prob_uti_covid, 
                                death_uti = prob_death_UTI_covid, 
                                death_notuti = prob_death_notUTI_covid),
                   srag = list(uti = prob_uti_srag, 
                               death_uti = prob_death_UTI_srag, 
                               death_notuti = prob_death_notUTI_srag))
}

# df = covid.dt
# 
# df.UTI = filter(df, !is.na(UTI) & UTI!=9)
# UTI_table = as.matrix(table(df.UTI$age_class, df.UTI$UTI))
# UTI_data = data.frame(UTIadmissions = UTI_table[,1], trials = rowSums(UTI_table), age_class = age_table$ID)
# 
# table_twitter = data.frame(faixas = prob_uti_covid$faixas,
#                            hospitalizados =  UTI_data$trials,
#                            hospitalizados_UTI = UTI_data$UTIadmissions,
#                            prob_UTI = prob_uti_covid$Estimate*100,
#                            mort_UTI = prob_death_UTI_covid$Estimate*100,
#                            mort_notUTI = prob_death_notUTI_covid$Estimate*100)
# write_csv(table_twitter, "~/Dropbox/table_twitter.csv")
# 
# xtable::xtable(table_twitter)

##################################
## Survival analysis
##################################

getTimes = function(x, late, early, censored = FALSE){  
  if(!censored){
    time = as.numeric(x[[late]] - x[[early]])
    data.frame(ID = x$ID, time = time, age_class = x$age_class, 
               early =  x[[early]], late = x[[late]])
  } else{
    if(is.na(x[[late]])){ 
      time = as.numeric(today() - x[[early]])
      censored = 0
    } else{
      time = as.numeric(x[[late]] -x[[early]])
      censored = 1
    } 
    data.frame(ID = x$ID, evolucao = x$evolucao, time = time, age_class = x$age_class, censored = censored,
               early =  x[[early]], late = x[[late]])
  }
}

plotTimesValidation = function(times_table, fit1, age = TRUE){
  if(age){
    sim_times = sapply(times_table$age_class, function(a) rwaittime_age(1, a, fit1))
    times_table$sim = sim_times
    times_table$age = age_table$faixas[match(times_table$age_class, age_table$ID)]
    d = pivot_longer(times_table, c(sim, time))
    ggplot(data = d, aes(x = value, group = name, fill = name)) + 
      geom_density(alpha= 0.5) + facet_wrap(~age) + 
      theme_cowplot() + scale_fill_discrete(labels = c("Simulado", "Observado"), name = "Categoria") 
  } else{
    sim_times = rwaittime(nrow(times_table), fit1)
    times_table$sim = sim_times
    d = pivot_longer(times_table, c(sim, time))
    ggplot(data = d, aes(x = value, group = name, fill = name)) + 
      geom_density(alpha= 0.5) + 
      theme_cowplot() + scale_fill_discrete(labels = c("Simulado", "Observado"), name = "Categoria") 
  }
}

# #save_plot(filename = "plots/survival_dist_byAge.png", p1, base_height = 3, ncol = 3, nrow = 3)
# 
# current_age = age_table$ID[1]
# ldply(age_table$ID, function(current_age) quantile(rwaittime_age(10000, current_age, fit1_hosp), c(0.1, 0.5, 0.9))) %>%
#   round(1) %>% mutate(age = age_table$faixas) %>% select(age, everything()) 



# tempo de hospitalização em leito comum, 

notUTIStay_covid = ddply(filter(covid.dt, UTI != 1), .(ID), getTimes, "dt_evo", "dt_int", censored = TRUE) %>% 
  mutate(time = time + 1) 
notUTIStay_srag  = ddply(filter(srag.dt,  UTI != 1), .(ID), getTimes, "dt_evo", "dt_int", censored = TRUE) %>% 
  mutate(time = time + 1) 
#qplot(data = notUTIStay_covid, x = time, geom = "histogram") + facet_wrap(~age_class)

fit0_notUTIStay_covid <- brm(time | cens(censored) ~ 1, 
                             data = notUTIStay_covid, family = weibull, inits = "0", 
                             prior = c(prior("normal(0, 1)", class = "Intercept"),
                                       prior("normal(0, 0.5)", class = "shape")),
                             control = list(adapt_delta = 0.99))
plotTimesValidation(notUTIStay_covid, fit0_notUTIStay_covid, FALSE)

fit0_notUTIStay_srag <- brm(time | cens(censored) ~ 1, 
                            data = notUTIStay_srag, family = weibull, inits = "0", 
                            prior = c(prior("normal(0, 1)", class = "Intercept"),
                                      prior("normal(0, 0.5)", class = "shape")),
                            control = list(adapt_delta = 0.99))
plotTimesValidation(notUTIStay_srag, fit0_notUTIStay_srag, FALSE)


fit1_notUTIStay_covid <- brm(time | cens(censored) ~ 1 + (1|age_class), 
                             data = notUTIStay_covid, family = weibull, inits = "0", 
                             prior = c(prior("normal(0, 1)", class = "sd"), 
                                       prior("normal(0, 1)", class = "Intercept"),
                                       prior("normal(0, 0.5)", class = "shape")),
                             control = list(adapt_delta = 0.99))
plotTimesValidation(notUTIStay_covid, fit1_notUTIStay_covid)


fit1_notUTIStay_srag <- brm(time | cens(censored) ~ 1 + (1|age_class), 
                            data = notUTIStay_srag, family = weibull, inits = "0", 
                            prior = c(prior("normal(0, 1)", class = "sd"), 
                                      prior("normal(0, 1)", class = "Intercept"),
                                      prior("normal(0, 0.5)", class = "shape")),
                            control = list(adapt_delta = 0.99))
plotTimesValidation(notUTIStay_srag, fit1_notUTIStay_srag)


if(all_models){
  notUTI_stay_times_covid = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                             c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                                  fit1_notUTIStay_covid) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  notUTI_stay_times_srag = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                            c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                                 fit1_notUTIStay_srag) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  
  write_csv(notUTI_stay_times_covid, EXPORT("notUTI_stay_times_covid"))
  write_csv(notUTI_stay_times_srag, EXPORT("notUTI_stay_times_srag"))
}
#em UTI, 

# Tempo entre Entrar e sair da UTI
UTIStay_covid = ddply(filter(covid.dt, UTI == 1), .(ID), getTimes, "dt_saiuti", "dt_entuti", censored = TRUE) %>% 
  mutate(time = time + 1) 
UTIStay_srag  = ddply(filter(srag.dt,  UTI == 1), .(ID), getTimes, "dt_saiuti", "dt_entuti", censored = TRUE) %>% 
  mutate(time = time + 1) %>% filter(time > 0)
#qplot(data = UTIStay_covid, x = time, geom = "histogram") + facet_wrap(~age_class)

fit0_UTIStay_covid <- brm(time | cens(censored) ~ 1, 
                          data = UTIStay_covid, family = weibull, inits = "0", 
                          prior = c(prior("normal(0, 1)", class = "Intercept"),
                                    prior("normal(0, 0.5)", class = "shape")),
                          control = list(adapt_delta = 0.99))
plotTimesValidation(UTIStay_covid, fit0_UTIStay_covid, FALSE)


fit0_UTIStay_srag <- brm(time | cens(censored) ~ 1, 
                         data = UTIStay_srag, family = weibull, inits = "0", 
                         prior = c(prior("normal(0, 1)", class = "Intercept"),
                                   prior("normal(0, 0.5)", class = "shape")),
                         control = list(adapt_delta = 0.99))
plotTimesValidation(UTIStay_srag, fit0_UTIStay_srag, FALSE)


fit1_UTIStay_covid <- brm(time | cens(censored) ~ 1 + (1|age_class), 
                          data = UTIStay_covid, family = weibull, inits = "0", 
                          prior = c(prior("normal(0, 1)", class = "sd"), 
                                    prior("normal(0, 1)", class = "Intercept"),
                                    prior("normal(0, 0.5)", class = "shape")),
                          control = list(adapt_delta = 0.99))
plotTimesValidation(UTIStay_covid, fit1_UTIStay_covid)

fit1_UTIStay_srag <- brm(time | cens(censored) ~ 1 + (1|age_class), 
                         data = UTIStay_srag, family = weibull, inits = "0", 
                         prior = c(prior("normal(0, 1)", class = "sd"), 
                                   prior("normal(0, 1)", class = "Intercept"),
                                   prior("normal(0, 0.5)", class = "shape")),
                         control = list(adapt_delta = 0.99))
plotTimesValidation(UTIStay_srag, fit1_UTIStay_srag)


if(all_models){
  UTI_stay_times_covid = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                          c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                               fit1_UTIStay_covid) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  UTI_stay_times_srag = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                         c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                              fit1_UTIStay_srag) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  
  write_csv(UTI_stay_times_covid, EXPORT("UTI_stay_times_covid"))
  write_csv(UTI_stay_times_srag, EXPORT("UTI_stay_times_srag"))
  
  
  meanUTI_stay_times_covid = llply(age_table$ID, 
                                   function(age, fit1){ 
                                     rwaittime_posterior_age(100, age, fit1)
                                   },
                                   fit1_UTIStay_covid) %>%
    llply(colMeans) %>% ldply(function(x) c(mean(x), sd(x))) %>%
    dplyr::rename(media = V1, sd = V2) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
}

## Tempo entre sintomas e internação

int_times_covid = ddply(covid.dt, .(ID), getTimes, late = "dt_int", early = "dt_sin") %>% 
  mutate(time = time + 1) %>% filter(time > 0)
int_times_srag  = ddply(srag.dt,  .(ID), getTimes, late = "dt_int", early = "dt_sin") %>% 
  mutate(time = time + 1) %>% filter(time > 0)  
#qplot(data = int_times_covid, x = time, geom = "histogram") + facet_wrap(~age_class)

fit0_int_covid <- brm(time ~ 1,
                      data = int_times_covid, family = weibull, inits = "0", 
                      prior =  c(prior("normal(0, 1)", class = "Intercept"),
                                 prior("normal(0, 0.5)", class = "shape")), 
                      control = list(adapt_delta = .99))
plotTimesValidation(int_times_covid, fit0_int_covid, FALSE)

fit0_int_srag <- brm(time ~ 1,
                     data = int_times_srag, family = weibull, inits = "0",
                     prior =  c(prior("normal(0, 1)", class = "Intercept"),
                                prior("normal(0, 0.5)", class = "shape")),
                     control = list(adapt_delta = 0.99))
plotTimesValidation(int_times_srag, fit0_int_srag, FALSE)


if(all_models){
  fit1_int_covid <- brm(time ~ 1 + (1|age_class), 
                        data = int_times_covid, family = weibull, inits = "0", 
                        prior =  c(prior("normal(0, 1)", class = "sd"), 
                                   prior("normal(0, 1)", class = "Intercept"),
                                   prior("normal(0, 0.5)", class = "shape")), 
                        control = list(adapt_delta = .99))
  plotTimesValidation(int_times_covid, fit1_int_covid)
  
  
  fit1_int_srag <- brm(time ~ 1 + (1|age_class), 
                       data = int_times_srag, family = weibull, inits = "0",
                       prior =  c(prior("normal(0, 1)", class = "sd"), 
                                  prior("normal(0, 1)", class = "Intercept"),
                                  prior("normal(0, 0.5)", class = "shape")),
                       control = list(adapt_delta = 0.99))
  plotTimesValidation(int_times_srag, fit1_int_srag)
  
  
  sint_int_times_covid = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                          c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                               fit1_int_covid) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  sint_int_times_srag = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                         c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                              fit1_int_srag) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  
  write_csv(sint_int_times_covid, EXPORT("sint_int_times_covid"))
  write_csv(sint_int_times_srag, EXPORT("sint_int_times_srag"))
}

# Tempo entre sair da UTI e evolução

UTIAfter_covid = ddply(filter(covid.dt, !is.na(dt_saiuti), dt_saiuti <= today(), UTI == 1, evolucao == 1), .(ID), getTimes, "dt_evo", "dt_saiuti", censored = FALSE)%>% 
  mutate(time = time + 1) %>% filter(time > 0) 
UTIAfter_srag  = ddply(filter(srag.dt,  !is.na(dt_saiuti), dt_saiuti <= today(), UTI == 1, evolucao == 2), .(ID), getTimes, "dt_evo", "dt_saiuti", censored = FALSE) %>% 
  mutate(time = time + 1) %>% filter(time > 0, time < 20) %>% arrange(desc(time))
#qplot(data = UTIAfter_srag, x = time, geom = "histogram", binwidth = 1)

fit0_AfterUTI_covid <- brm(time ~ 1, 
                           data = UTIAfter_covid, family = weibull, inits = "0", 
                           prior =c(prior("normal(0, 0.05)", class = "Intercept"),
                                    prior("normal(0, 0.5)", class = "shape")), 
                           control = list(adapt_delta = 0.99))
plotTimesValidation(UTIAfter_covid, fit0_AfterUTI_covid, FALSE)

fit0_AfterUTI_srag <- brm(time ~ 1, 
                          data = UTIAfter_srag, family = weibull, inits = "0", 
                          prior =c(prior("normal(0, 0.05)", class = "Intercept"),
                                   prior("normal(0, 0.5)", class = "shape")), 
                          control = list(adapt_delta = 0.99))
plotTimesValidation(UTIAfter_srag, fit0_AfterUTI_srag, FALSE)

if(all_models){
  fit1_AfterUTI_covid <- brm(time ~ 1 + (1|age_class), 
                             data = UTIAfter_covid, family = weibull, inits = "0", 
                             prior =c(prior("normal(0, 0.05)", class = "sd"), 
                                      prior("normal(0, 1)", class = "Intercept"),
                                      prior("normal(0, 0.5)", class = "shape")), 
                             control = list(adapt_delta = 0.99))
  plotTimesValidation(UTIAfter_covid, fit1_AfterUTI_covid)
  
  
  fit1_AfterUTI_srag <- brm(time ~ 1 + (1|age_class), 
                            data = UTIAfter_srag, family = weibull, inits = "0", 
                            prior =c(prior("normal(0, 0.05)", class = "sd"), 
                                     prior("normal(0, 1)", class = "Intercept"),
                                     prior("normal(0, 0.5)", class = "shape")), 
                            control = list(adapt_delta = 0.99))
  plotTimesValidation(UTIAfter_srag, fit1_AfterUTI_srag)
  
  
  afterUTI_times_covid = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                          c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                               fit1_AfterUTI_covid) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  afterUTI_times_srag = ldply(age_table$ID, function(age, fit1) quantile(rwaittime_posterior_age(100, age, fit1), 
                                                                         c(0.025, 0.2, 0.5, 0.8, 0.975)), 
                              fit1_AfterUTI_srag) %>% mutate(faixas = age_table$faixas) %>% select(faixas, everything())
  
  write_csv(afterUTI_times_covid, EXPORT("afterUTI_times_covid"))
  write_csv(afterUTI_times_srag, EXPORT("afterUTI_times_srag"))
}



if(all_models){
  time_fits1 = list(covid = list(notUTI   = fit1_notUTIStay_covid, 
                                 UTI      = fit1_UTIStay_covid, 
                                 Int      = fit1_int_covid, 
                                 afterUTI = fit1_AfterUTI_covid),
                    srag  = list(notUTI   = fit1_notUTIStay_srag, 
                                 UTI      = fit1_UTIStay_srag, 
                                 Int      = fit1_int_srag, 
                                 afterUTI = fit1_AfterUTI_srag))
} else{
  load(C("hospitalStatsFits.Rdata"))
  time_fits1$covid$notUTI = fit1_notUTIStay_covid
  time_fits1$srag$notUTI = fit1_notUTIStay_srag
}

time_fits0 = list(covid = list(notUTI   = fit0_notUTIStay_covid, 
                               UTI      = fit0_UTIStay_covid, 
                               Int      = fit0_int_covid, 
                               afterUTI = fit0_AfterUTI_covid),
                  srag  = list(notUTI   = fit0_notUTIStay_srag, 
                               UTI      = fit0_UTIStay_srag, 
                               Int      = fit0_int_srag, 
                               afterUTI = fit0_AfterUTI_srag))

save(time_fits0, time_fits1, probsFits, 
     file = C("hospitalStatsFits.Rdata"))
# sim_hosp = sapply(hospitalization_times$age_class, function(a) rwaittime_age(1, a, fit1_hosp))
# hospitalization_times$sim = sim_hosp
# hospitalization_times$age = age_table$faixas[match(hospitalization_times$age_class, age_table$ID)]
# d = pivot_longer(hospitalization_times, c(sim, time))
# p1 = ggplot(data = d, aes(x = value, group = name, fill = name)) + 
#   geom_density(alpha= 0.5) + facet_wrap(~age) + 
#   theme_cowplot() + scale_fill_discrete(labels = c("Simulado", "Observado"), name = "Categoria") 
# #save_plot(filename = "plots/survival_dist_byAge.png", p1, base_height = 3, ncol = 3, nrow = 3)
# 
# current_age = age_table$ID[1]
# ldply(age_table$ID, function(current_age) quantile(rwaittime_age(10000, current_age, fit1_hosp), c(0.1, 0.5, 0.9))) %>%
#   round(1) %>% mutate(age = age_table$faixas) %>% select(age, everything()) 

