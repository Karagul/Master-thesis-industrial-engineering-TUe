####################################################################################################
######                      DCC-GARCH Student-t distributed errors (rugarch)                 #######
####################################################################################################
# Two-stage quasi-likelihood function to find parameters under multivariate normal distributed errors
dcc_garch_modeling <- function(data=a_t, t=t, distribution.model="norm", distribution="mvnorm") {
  D_t_file <- matrix(NaN, T, N)
  colnames(D_t_file) <- c(colnames(data))[1:N]
  R_t_file <- matrix(NaN, T, N*(N-1)/2)
  cl = makePSOCKcluster(10)
  for (i in seq_along(t)) {  # tranquil: {1720:2223}, voaltile: {3225:3734}
    tic <- Sys.time()
    data_train <- data[1:t[i],1:N]  # Rolling forward: data[i:t[i],1:N]  
    # Specificaiton for component conditional volatilities
    univ_garch_spec <- ugarchspec(variance.model=list(model="gjrGARCH", garchOrder=c(1, 1)),
                                  mean.model=list(armaOrder=c(0,0), include.mean=FALSE), distribution.model=distribution.model)
    # if (distribution.model=="norm"){
    # univ_garch_spec <- ugarchspec(variance.model=list(model="fGARCH", submodel="GARCH", garchOrder=c(1, 1)),
    #                               mean.model=list(armaOrder=c(0,0), include.mean=FALSE), distribution.model=distribution.model)
    # } else{
    # univ_garch_spec <- ugarchspec(variance.model=list(model="gjrGARCH", garchOrder=c(1, 1)),
    #                               mean.model=list(armaOrder=c(0,0), include.mean=FALSE), distribution.model=distribution.model)
    # }
    multi_univ_garch_spec <- multispec(replicate(N,univ_garch_spec))
    # Specify DCC-GARCH(1,1) with multivariate Student-t errors for stand. residual series
    dcc_spec <- dccspec(multi_univ_garch_spec, dccOrder=c(1,1), model="DCC", distribution=distribution)
    # Fit component series
    fit.multi_garch <- multifit(multi_univ_garch_spec, data_train, cluster=cl)
    # Estimate DCC-GARCH(1,1) mvt model
    fit.dcc = dccfit(dcc_spec, data=data_train, solver='solnp', cluster=cl, fit.control=list(eval.se = FALSE), fit=fit.multi_garch)
    # Save conditional volatilities and correlations
    uniGarch.forc <- multiforecast(fit.multi_garch, n.ahead=1, n.roll=0, cluster=cl) # T+1 forecasts conditional volatilities
    dcc.forc <- dccforecast(fit.dcc, n.ahead=1, n.roll=0, cluster=cl)  # T+1 forecasts
    D_t_file[i, ] <- as.numeric(sigma(uniGarch.forc))
    R_t_file[i, ] <- t(dcc.forc@mforecast[["R"]][[1]][,,1])[lower.tri(t(dcc.forc@mforecast[["R"]][[1]][,,1]),diag=FALSE)]
    print(i)
    print(t[i])
    print(Sys.time()-tic)
  }
  stopCluster(cl)
  return(list("D_t_file"=D_t_file, "R_t_file"=R_t_file))
}

####################################################################################################
######                                Value-at-Risk Estimation                               #######
####################################################################################################
cor_mat <- function(cor_vec, dim) { # function assumes row matrix indexing
  # cor_vec := vector with uppertriangular correlation values index by row
  R_t <- matrix(0,dim,dim)
  R_t[lower.tri(R_t, diag=FALSE)] <- as.numeric(cor_vec)
  R_t <- t(R_t)
  R_t[lower.tri(R_t, diag=FALSE)] <- t(R_t)[lower.tri(R_t, diag=FALSE)]
  diag(R_t) <- rep(1, times=dim)
  if (isSymmetric(R_t) == FALSE) {
    print("Houston we have a problem, our correlation matrix is not symmetric!")
  }
  return(R_t)
}

cov_mat_portfolio <- function(vol_vec, cor_vec) {
  D_t <- diag(as.numeric(vol_vec))
  R_t <- cor_mat(cor_vec, dim=length(vol_vec))   # Symmetric matrix from upper triangular matrix
  H_t <- D_t %*% R_t %*% D_t  # Conditional covariance matrix 
  return(H_t)
}

portfolio_VaR <- function(volatility_matrix, cor_matrix, mu_portfolio_loss, alpha, file, T=T, w=w) {
  # volatility_matrix := matrix with conditional volatilities
  # cor_matrix := matrix with conditional correlations
  sigma_t <- rep(NaN,T)
  for (i in 1:T) {
    H_t <- cov_mat_portfolio(volatility_matrix[i,], cor_matrix[i,])
    sigma_t[i] <- sqrt(t(w)%*%H_t%*%w)  # Portfolio std
  }
  result = VaR_estimates(sigma_portfolio=sigma_t, mu=mu_portfolio_loss, cl=alpha)
  VaR_t = result$var
  CVaR_t = result$cvar
  write.csv(VaR_t, file=file) 
  return(list("var"=VaR_t, "cvar"=CVaR_t))
}

VaR_estimates <- function(sigma_portfolio, mu, cl) {
  VaR_mat <- matrix(data=NaN, nrow=T, ncol=length(cl))
  CVaR_vec <- matrix(data=NaN, nrow=1, ncol=T)
  colnames(VaR_mat) <- 1-cl  #  Set column names to corresponding conf. level VaR estimates
  for (i in 1:length(sigma_portfolio)) {
    for (a in cl) {
      #VaR_mat[i, toString(a)] <- mu+sigma_portfolio[i]*qnorm(1-a)  # norm 1994-1995
      VaR_mat[i, toString(a)] <- mu+sigma_portfolio[i]*sqrt((6.9-2) / 6.9)*qt(p=(1-a), df=6.9) # Studen t 2000-2001. sqrt(v-2/2): to take account that the error distribution is scaled to have variance one.
      if (a==0.99) {
      #CVaR_vec[i] <- mu-sigma_portfolio[i]*(dnorm(qnorm(a)) / (1-a)) # norm 1994-1995
      CVaR_vec[i] <- mu-sigma_portfolio[i]*sqrt((6.9-2) / 6.9)* (dt(qt(p=a, df=6.9), df=6.9) / (1-a)) * ((6.9+(qt(p=a, df=6.9))^2) / (6.9-1))   # Student t 2000-2001
      }
    }
  }
  return(list("var"=VaR_mat, "cvar"=CVaR_vec))
}

####################################################################################################
######                                Value-at-Risk Backtesting                              #######
####################################################################################################
# Kupiec's Unconditional Coverage Test & Christoffersen Markov Test for independence 
uc_ind_test <- function(VaR_est, cl, file) {
  # Initialise datastructure to save test results
  row_names <- c("exceedances", "LR_pof", "LR_crit_pof", "decision_pof",
                 "pi01", "pi11", "LR_ind", "LR_crit_ind", "decision_ind")
  Kupiec_Christoffersen_mat <- matrix(data=NaN, nrow=length(row_names), ncol=length(cl))
  colnames(Kupiec_Christoffersen_mat) <- 1-cl  #  Set column names to corresponding conf. level VaR estimates
  rownames(Kupiec_Christoffersen_mat) <- row_names
  Kupiec_Christoffersen_mat
  for (a in cl) {
    I_sum <- sum(VaR_true<VaR_est[,toString(1-a)])   # Sum of exceedances
    LR_pof <- 2*log((((1-(I_sum/T))/(1-a))^(T-I_sum))*(((I_sum/T)/a)^I_sum))
    LR_crit_pof <- qchisq(p=0.95, df=1)  # Coverage test with significance level 0.95 
    decision_pof <- ifelse(LR_pof > LR_crit_pof, "Reject H0", "Fail to reject H0")
    # Compute Markov test numbers
    I <- ifelse(VaR_true<VaR_est[,toString(1-a)], 1, 0)  #  Hit function series
    T_00=T_10=T_01=T_11 <- 0  # Markov test numbers
    for (i in 2:nrow(VaR_est)) {  
      T_00 <- ifelse(I[i-1]==0 & I[i]==0, T_00+1, T_00)
      T_10 <- ifelse(I[i-1]==1 & I[i]==0, T_10+1, T_10)
      T_01 <- ifelse(I[i-1]==0 & I[i]==1, T_01+1, T_01)
      T_11 <- ifelse(I[i-1]==1 & I[i]==1, T_11+1, T_11)
    }
    # Compute Markov transition probabilities
    pi_01=pi_11 <- 0          
    pi_01 <- T_01 / (T_00+T_01)
    pi_11 <- T_11 / (T_10+T_11)
    pi_2 <- (T_01+T_11) / (T_00+T_10+T_01+T_11)
    LR_ind <- -2*log(((1-pi_2)^(T_00+T_10)*pi_2^(T_01+T_11)) / 
                       ((1-pi_01)^T_00*pi_01^T_01*(1-pi_11)^T_10*pi_11^T_11))
    LR_crit_ind <- qchisq(p=0.95, df=1)  # Coverage test with significance level 0.95 
    decision_ind <- ifelse(LR_ind > LR_crit_ind, "Reject H0", "Fail to reject H0")
    Kupiec_Christoffersen_mat[, toString(1-a)] <- c(I_sum, LR_pof, LR_crit_pof,decision_pof,
                                                    pi_01, pi_11, LR_ind, LR_crit_ind, decision_ind)
  }
  write.csv(Kupiec_Christoffersen_mat, file=file) 
  return(Kupiec_Christoffersen_mat)
}


regions_uc_test <- function(T=T, alpha=alpha, eps=0.05) {
  " Use binomial distribution (hit sequence) to construct non-rejection regions."
  # T: length backtest period
  # alpha: confidence level VaR
  # eps: significance level test 
  q <- 1-alpha
  lb_init <- qbinom(p=(eps/2), size=T, prob=q)  # 1: P(X < lb_init) <= eps/2
  # Find maximum x1 for which (1) holds 
  if(pbinom(q=lb_init, size=T, prob=q) > (eps/2)) {
    lb_init <- lb_init-1
  }
  ub_init <- qbinom(p=(eps/2), size=T, prob=q, lower.tail=FALSE)
  if(pbinom(q=ub_init, size=T, prob=q, lower.tail=FALSE) > (eps/2)) {
    ub_init <- ub_init+1
  }
  # [a, b]
  op_1 <- pbinom(q=lb_init, size=T, prob=q) + pbinom(q=ub_init, size=T, prob=q, lower.tail=FALSE)
  lb_opt <- lb_init
  ub_opt <- ub_init
  op_opt <- op_1
  # [a+1, b]
  op_2 <- pbinom(q=lb_init+1, size=T, prob=q) + pbinom(q=ub_init, size=T, prob=q, lower.tail=FALSE)
  if ((op_2 <= eps) & (eps-op_2 <= eps-op_opt)) {
    lb_opt <- lb_init+1
    ub_opt <- ub_init
    op_opt <- op_2
  }
  # [a, b-1]
  op_3 <- pbinom(q=lb_init, size=T, prob=q) + pbinom(q=ub_init-1, size=T, prob=q, lower.tail=FALSE)
  if ((op_3 <= eps) & (eps-op_3 <= eps-op_opt)) {  
    lb_opt <- lb_init
    ub_opt <- ub_init-1
    op_opt <- op_3
  }
  return(list("lb"=lb_opt+1, "ub"=ub_opt))
}

cvar_analysis <- function(cvar_matrix, var_true, period='tranquil', var_files=NULL, file=NULL) {
  # Initialise datastructure to save test results
  row_names <- rownames(cvar_matrix)
  col_names <- c('min(er_t)', 'E[er_t]')
  cvar_analysis_mat <- matrix(data=NaN, nrow=length(row_names), ncol=length(col_names))
  rownames(cvar_analysis_mat) <- row_names
  colnames(cvar_analysis_mat) <- col_names
  for (row_name in row_names) {
    var_file <- grep(row_name, var_files, value=TRUE)
    var_est = read.table(paste("VaR/", period, "/", var_file, sep=""), sep=",", skip=1)
    var_est = var_est[, ncol(var_est)]
    idx <- which(var_true < var_est)  # Which indices correspond to VaR exceedances
    x <- sapply(c(idx), function(x) var_true[x] - cvar_mat[row_name, x])
    cvar_analysis_mat[row_name, col_names[1]] <- min(x)
    cvar_analysis_mat[row_name, col_names[2]] <- mean(x)
  }
  write.csv(cvar_analysis_mat, file=file) 
  return(list("cvar_analysis"=cvar_analysis_mat))
}


  
  
  
  
  
  

