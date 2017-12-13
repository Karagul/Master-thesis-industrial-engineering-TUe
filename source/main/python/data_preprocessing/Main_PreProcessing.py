#from pandas_datareader import data as dt

from PreProcessor import PreProcessor
from ModuleManager import ModuleManager
from TechnicalAnalyzer import TechnicalAnalyzer
from sklearn.ensemble import RandomForestRegressor
from sklearn.neighbors import KNeighborsRegressor

from sklearn.metrics import precision_score

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.stats.stats import pearsonr
import time
from math import sqrt, exp

from sklearn.metrics import mean_absolute_error
from sklearn.metrics import mean_squared_error # use mse to penalize outliers more

#  Set seed for pseudorandom number generator. This allows us to reproduce the results from our script.
#np.random.seed(30)  # globally set random seed  (30 is a good option) 21 days
np.random.seed(30)


def main():

    preprocesser = PreProcessor()
    mm = ModuleManager()
    ta = TechnicalAnalyzer()
    # ft = FeatureNormalizer()


    ##################################################################################################################
    ###     Asset path simulation using Cholesky Factorization and predefined time-varying correlation dynamics    ###
    ################## ################################################################################################
    """
    T = 1751
    a0 = 0.1
    a1 = 0.8
    random_corr = preprocesser.simulate_random_correlation_ar(T, a0, a1)
    vol_matrix = np.array([[0.08, 0],  # Simple volatility matrix with unit variances for illustration purposes
                           [0, 0.1]])

    correlated_asset_paths = preprocesser.simulate_correlated_asset_paths(random_corr, vol_matrix, T)

    plt.title('Simulated data using Cholesky decomposition and time-varying correlations')
    plt.plot(correlated_asset_paths[1200:, 0], label='$y_{1,t}$', linewidth=1, color='black')
    plt.plot(correlated_asset_paths[1200:, 1], label='$y_{2,t}$', linewidth=1, linestyle='--', color='blue')
    plt.plot(random_corr[1200:], label='$\\rho_t$', linewidth=1, color='red')
    plt.legend(fontsize='small', bbox_to_anchor=(1, 0.22), fancybox=True)
    plt.xlim(0, 500)
    plt.ylim(-0.5, 1)
    #plt.show()

    data = pd.DataFrame(correlated_asset_paths)
    data['rho'] = random_corr
    mm.save_data('correlated_sim_data.pkl', data)
    """
    ##################################################################################################################
    ###     Estimation uncertainty in (weighted) Pearson correlation coefficient using moving window estimates     ###
    ##################################################################################################################
    """
    simulated_data_process = mm.load_data('/bivariate_analysis/correlated_sim_data.pkl')
    T = 500
    delta_t = 10
    ciw = 99

    #start_time = time.time()
    rho_estimates, lower_percentiles, upper_percentiles = \
        preprocesser.bootstrap_moving_window_estimate(simulated_data_process, delta_t=delta_t, T=T, ciw=ciw,
                                                      weighted=False)
    #print("%s: %f" % ('Execution time:', (time.time() - start_time)))
    """
    """
    # Figure
    plt.figure(0)
    #plt.plot(rho_true, label='real correlation', linewidth=1, color='black')
    plt.plot(rho_estimates, label='MW correlation', linewidth=1, color='red')
    plt.plot(lower_percentiles, label='%d%% interval (bootstrap)' % ciw, linewidth=1,
             color='magenta')
    plt.plot(upper_percentiles, linewidth=1, color='magenta')
    plt.title('MW estimates with window size %i' % delta_t)
    plt.xlabel('observation')
    plt.legend(loc='lower right', fancybox=True)
    plt.xlim(0, T)
    plt.yticks(np.arange(-1, 1.00000001, 0.2))
    plt.ylim(-1, 1)
    plt.show()
    """
    ##################################################################################################################
    ###       Mean squared error of (weighted) Pearson correlation coefficient using moving window estimates       ###
    ##################################################################################################################
    """
    simulated_data_process = mm.load_data('/bivariate_analysis/correlated_sim_data.pkl')
    T = 500
    rho_true = simulated_data_process.tail(T).iloc[:, -1]
    delta_t_min = 3
    delta_t_max = 252
    mse_mw_vec = np.full(delta_t_max-1, np.nan)
    mse_emw_vec = np.full(delta_t_max-1, np.nan)

    for dt in range(delta_t_min, delta_t_max):
        mw_estimates = simulated_data_process.tail(T+dt-1).iloc[:, 0].rolling(window=dt).corr(
            other=simulated_data_process.tail(T+dt-1)[1])
        emw_estimates = ta.pearson_weighted_correlation_estimation(simulated_data_process.tail(T+dt-1).iloc[:, 0],
                                                                   simulated_data_process.tail(T+dt-1)[1], dt)
        mse_mw_vec[dt - 1] = mean_squared_error(rho_true, mw_estimates.tail(T))
        mse_emw_vec[dt - 1] = mean_squared_error(rho_true, emw_estimates[-T:])

    mm.save_data('mse_mw_true_corr.pkl', mse_mw_vec)
    mm.save_data('mse_emw_true_corr.pkl', mse_emw_vec)

    mse_mw_vec = mm.load_data('mse_mw_true_corr.pkl')
    mse_emw_vec = mm.load_data('mse_emw_true_corr.pkl')

    # Figure
    plt.figure(1)
    plt.plot(mse_mw_vec, label='Moving Window', color='blue')
    plt.plot(mse_emw_vec, label='Exp. Weighted Moving Window', color='red')
    plt.title('MSE for MW and EMW')
    plt.xlabel('window length')
    plt.ylabel('MSE')
    plt.legend(loc='upper right', fancybox=True)
    plt.xlim(0, 250)
    plt.ylim(0, 0.5)
    plt.show()
    """

    ##################################################################################################################
    ###                                          Dataset creation                                                  ###
    ##################################################################################################################
    # Pearson correlation moving window estimates as covariates and true correlation as response variable
    """
    simulated_data_process = mm.load_data('correlated_sim_data.pkl')
    delta_t_min = 3
    delta_t_max = 4
    start_time = time.time()
    for dt in range(delta_t_min, delta_t_max):
        dataset = preprocesser.generate_bivariate_dataset(ta, simulated_data_process, dt, weighted=False)
        mm.save_data('/bivariate_analysis/emw/dataset_emw_%d.pkl' % dt, dataset)

    print("%s: %f" % ('Execution time:', (time.time() - start_time)))
    """

    """
    mse_knn_mw_vec = mm.load_data('mse_knn_mw_true_corr.pkl')
    mse_knn_emw_vec = mm.load_data('mse_knn_emw_true_corr.pkl')
    mse_mw_vec = mm.load_data('mse_mw_true_corr.pkl')

    #mse_mw_vec = mm.load_data('mse_mw_true_corr.pkl')
    #plt.plot(mse_mw_vec, label='Moving Window')
    #plt.plot(mse_emw_vec, label='Exp. Weighted Moving Window')
    plt.plot(mse_knn_mw_vec, label='KNN_mw')
    plt.plot(mse_knn_emw_vec, label='KNN_emw')
    plt.plot(mse_mw_vec, label='MW')
    plt.title('MSE for KNN')
    plt.xlabel('window length')
    plt.ylabel('MSE')
    plt.legend(loc='lower right', fancybox=True)
    plt.ylim(0.06, 0.10)
    plt.xlim(0, 250)
    plt.show()
    """

    ##################################################################################################################
    ###    Estimation uncertainty in (weighted) Pearson correlation coefficient using machine learner estimates    ###
    ##################################################################################################################
    T = 500
    ciw = 99
    reps = 1000
    delta_t = [21, 251]
    model = 'knn'
    proxy_type = ['mw', 'emw']

    start_time = time.time()
    for dt, proxy_type in [(x, y) for x in delta_t for y in proxy_type]:
        dataset = mm.load_data('bivariate_analysis/%s/dataset_%s_%i.pkl' % (proxy_type, proxy_type, dt))
        rho_estimates, lower_percentiles, upper_percentiles = \
        preprocesser.bootstrap_learner_estimate(data=dataset, reps=reps, model=model)
        data_frame = pd.DataFrame({'Percentile_low': lower_percentiles, 'Percentile_up': upper_percentiles,
                                    'Rho_estimate': rho_estimates})
        filename = '%s_%s_%i_estimate_uncertainty.pkl' % (model, proxy_type, dt)
        mm.save_data('bivariate_analysis/' + filename, data_frame)
        print(data_frame.head())

    print("%s: %f" % ('Execution time', (time.time() - start_time)))

    # Figure
    """
    plt.figure(0)
    # plt.plot(rho_true, label='real correlation', linewidth=1, color='black')
    plt.plot(rho_estimates, label='KNN correlation', linewidth=1, color='red')
    plt.plot(lower_percentiles, label='%d%% interval (bootstrap)' % ciw, linewidth=1, color='magenta')
    plt.plot(upper_percentiles, linewidth=1, color='magenta')

    plt.title('KNN estimates with window size %i' % delta_t)
    plt.xlabel('observation')
    plt.legend(loc='lower right', fancybox=True)
    plt.xlim(0, T)
    plt.yticks(np.arange(-1, 1.00000001, 0.2))
    plt.ylim(-1, 1)
    plt.show()
    """


    """
    # Prepare models
    models = []
    models.append(('KNN', KNeighborsRegressor()))  # Option: weights='distance'
    for name, model in models:
        rho_estimates, lower_percentiles, upper_percentiles = \
            preprocesser.bootstrap_learner_estimate(dataset)
    """



















    



###############################
####         MAIN          ####
###############################
if __name__ == '__main__':
    main()