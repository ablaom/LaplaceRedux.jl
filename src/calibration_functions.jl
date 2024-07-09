using Statistics
using Distributions: Normal, Bernoulli
@doc raw""" 
    empirical_frequency_regression(Y_cal, sampled_distributions, n_bins=20)

FOR REGRESSION MODELS.  \
Given a calibration dataset ``(x_t, y_t)`` for ``i ∈ {1,...,T}`` and an array of sampled predicted distributions, the function calculates the empirical frequency
```math
p^hat_j = {y_t|F_t(y_t)<= p_j, t= 1,....,T}/T,
```
where ``T`` is the number of calibration points, ``p_j`` is the confidence level and ``F_t`` is the 
cumulative distribution function of the predicted distribution targeting ``y_t``. \
Source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs: \
    - `Y_cal`: a vector of values ``y_t``\
    - `sampled_distributions`: a Vector{Vector{Float64}} of sampled distributions stacked row-wise.\
        For example [rand(distr,50) for distr in LaplaceRedux.predict(la,X)]
    - `n_bins`: number of equally spaced bins to use.\
Outputs:\
    - `counts`: an array cointaining the empirical frequencies for each quantile interval.
"""
function empirical_frequency_regression(Y_cal, sampled_distributions; n_bins::Int=20)
    if n_bins <= 0
        throw(ArgumentError("n_bins must be a positive integer"))
    end
    n_edges = n_bins + 1
    quantiles = collect(range(0; stop=1, length=n_edges))
    quantiles_matrix = hcat(
        [
            map(Base.Fix1(quantile, samples), quantiles) for
            samples in sampled_distributions
        ]...,
    )
    n_rows = size(quantiles_matrix, 1)
    counts = Float64[]
    for i in 1:n_rows
        push!(counts, sum(Y_cal .<= quantiles_matrix[i, :]) / length(Y_cal))
    end
    return counts
end

@doc raw""" 
    sharpness_regression(sampled_distributions)

FOR REGRESSION MODELS.  \
Given a calibration dataset ``(x_t, y_t)`` for ``i ∈ {1,...,T}`` and an array of sampled predicted distributions, the function calculates the 
sharpness of the sampled predicted distributions, i.e., the average of the variances ``\sigma^2(F_t)`` predicted by the forecaster for each ``x_t``. \
source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs: \
    - `sampled_distributions`: an array of sampled distributions ``F(x_t)`` stacked column-wise. \
Outputs: \
    - `sharpness`: a scalar that measure the level of sharpness of the regressor
"""
function sharpness_regression(sampled_distributions)
    sharpness = mean(var.(sampled_distributions))
    return sharpness
end

@doc raw""" 
    empirical_frequency_classification(y_binary, sampled_distributions)

FOR BINARY CLASSIFICATION MODELS.\
Given a calibration dataset ``(x_t, y_t)`` for ``i ∈ {1,...,T}`` let ``p_t= H(x_t)∈[0,1]`` be the forecasted probability. \
We group the ``p_t`` into intervals ``I_j`` for ``j= 1,2,...,m`` that form a partition of [0,1]. 
The function computes the observed average ``p_j= T^-1_j ∑_{t:p_t ∈ I_j} y_j`` in each interval ``I_j``.  \
Source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs: \
    - `y_binary`: the array of outputs ``y_t`` numerically coded: 1 for the target class, 0 for the null class. \
    - `sampled_distributions`: an array of sampled distributions stacked column-wise so that in the first row 
        there is the probability for the target class ``y_1`` and in the second row the probability for the null class ``y_0``. \
    - `n_bins`: number of equally spaced bins to use.

Outputs: \
    - `num_p_per_interval`: array with the number of probabilities falling within interval. \
    - `emp_avg`: array with the observed empirical average per interval. \
    - `bin_centers`: array with the centers of the bins. 

"""
function empirical_frequency_binary_classification(
    y_binary, sampled_distributions; n_bins::Int=20
)
    if n_bins <= 0
        throw(ArgumentError("n_bins must be a positive integer"))
    elseif !all(x -> x == 0 || x == 1, y_binary)
        throw(ArgumentError("y_binary must be an array of 0 and 1"))
    end
    #intervals boundaries
    n_edges = n_bins + 1
    int_bds = collect(range(0; stop=1, length=n_edges))
    #bin centers
    bin_centers = [(int_bds[i] + int_bds[i + 1]) / 2 for i in 1:(length(int_bds) - 1)]
    #initialize list for empirical averages per interval 
    emp_avg = []
    #initialize list for predicted averages per interval
    pred_avg = []
    # initialize list of number of probabilities falling within each intervals
    num_p_per_interval = []
    #list of the predicted probabilities for the target class
    class_probs = sampled_distributions[1, :]
    # iterate over the bins
    for j in 1:n_bins
        push!(num_p_per_interval, sum(int_bds[j] .< class_probs .<= int_bds[j + 1]))
        if num_p_per_interval[j] == 0
            push!(emp_avg, 0)
            push!(pred_avg, bin_centers[j])

        else
            # find the indices fo all istances for which class_probs fall withing the j-th interval
            indices = findall(x -> int_bds[j] < x <= int_bds[j + 1], class_probs)
            #compute the empirical average and saved it in emp_avg in the j-th position
            push!(emp_avg, 1 / num_p_per_interval[j] * sum(y_binary[indices]))
            #TO DO: maybe substitute to bin_Centers?
            push!(pred_avg, 1 / num_p_per_interval[j] * sum(class_probs[indices]))
        end
    end
    #return the tuple
    return (num_p_per_interval, emp_avg, bin_centers)
end

@doc raw""" 
    sharpness_classification(y_binary,sampled_distributions)

FOR BINARY CLASSIFICATION MODELS.  \
Assess  the sharpness of the model by looking at the distribution of model predictions.  
When forecasts are sharp, most predictions are close to either 0 or 1   \
Source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs:  \
    - `y_binary`: the array of outputs  ``y_t``  numerically coded: 1 for the target class, 0 for the negative result.  \
    - `sampled_distributions`: an array of sampled distributions stacked column-wise so that in the first row there is the probability for the target class ``y_1`` and in the second row the probability for the null class ``y_0``.  \

Outputs:  \
    -  `mean_class_one`: a scalar that measure the average prediction for the target class  \
    -  `mean_class_zero`: a scalar that measure the average prediction for the null class  

"""
function sharpness_classification(y_binary, sampled_distributions)
    mean_class_one = mean(sampled_distributions[1, findall(y_binary .== 1)])
    mean_class_zero = mean(sampled_distributions[2, findall(y_binary .== 0)])
    return mean_class_one, mean_class_zero
end

@doc raw""" 
    sharpness_regression(distributions::Distributions.Normal)
Dispatched version for Normal distributions
FOR REGRESSION MODELS.  \
Given a calibration dataset ``(x_t, y_t)`` for ``i ∈ {1,...,T}`` and an array of predicted distributions, the function calculates the 
sharpness of the predicted distributions, i.e., the average of the variances ``\sigma^2(F_t)`` predicted by the forecaster for each ``x_t``. \
source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs: \
    - `distributions`: an array of normal distributions ``F(x_t)`` stacked row-wise. \
Outputs: \
    - `sharpness`: a scalar that measure the level of sharpness of the regressor
"""
function sharpness_regression(distributions::Vector{Normal{Float64}})
    sharpness = mean(var.(distributions))
    return sharpness
end

@doc raw""" 
    empirical_frequency_regression(Y_cal, distributions::Distributions.Normal, n_bins=20)
Dispatched version for Normal distributions
FOR REGRESSION MODELS.  \
Given a calibration dataset ``(x_t, y_t)`` for ``i ∈ {1,...,T}`` and an array of predicted distributions, the function calculates the empirical frequency
```math
p^hat_j = {y_t|F_t(y_t)<= p_j, t= 1,....,T}/T,
```
where ``T`` is the number of calibration points, ``p_j`` is the confidence level and ``F_t`` is the 
cumulative distribution function of the predicted distribution targeting ``y_t``. \
Source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs: \
    - `Y_cal`: a vector of values ``y_t``\
    - `distributions`:a Vector{Distributions.Normal{Float64}} of distributions stacked row-wise.\
        For example the output of LaplaceRedux.predict(la,X_cal)
    - `n_bins`: number of equally spaced bins to use.\
Outputs:\
    - `counts`: an array cointaining the empirical frequencies for each quantile interval.
"""
function empirical_frequency_regression(
    Y_cal, distributions::Vector{Normal{Float64}}; n_bins::Int=20
)
    if n_bins <= 0
        throw(ArgumentError("n_bins must be a positive integer"))
    end
    n_edges = n_bins + 1
    quantiles = collect(range(0; stop=1, length=n_edges))
    quantiles_matrix = hcat(
        [map(Base.Fix1(quantile, distr), quantiles) for distr in distributions]...
    )#warning deprecated, need to change in not sure what
    n_rows = size(quantiles_matrix, 1)
    counts = Float64[]

    for i in 1:n_rows
        push!(counts, sum(Y_cal .<= quantiles_matrix[i, :]) / length(Y_cal))
    end
    return counts
end

@doc raw""" 
    sharpness_classification(y_binary,distributions::Distributions.Bernoulli)
dispatched for Bernoulli Distributions
FOR BINARY CLASSIFICATION MODELS.  \
Assess  the sharpness of the model by looking at the distribution of model predictions.  
When forecasts are sharp, most predictions are close to either 0 or 1   \
Source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs:  \
    - `y_binary`: the array of outputs  ``y_t``  numerically coded: 1 for the target class, 0 for the negative result.  \
    - `distributions`: an array of Bernoulli distributions describing the probability of of the output belonging to the target class \

Outputs:  \
    -  `mean_class_one`: a scalar that measure the average prediction for the target class  \
    -  `mean_class_zero`: a scalar that measure the average prediction for the null class  

"""
function sharpness_classification(y_binary, distributions::Vector{Bernoulli{Float64}})
    mean_class_one = mean(mean.(distributions[findall(y_binary .== 1)]))
    mean_class_zero = mean(1 .- mean.(distributions[findall(y_binary .== 0)]))
    return mean_class_one, mean_class_zero
end

@doc raw""" 
    empirical_frequency_classification(y_binary, distributions::Distributions.Bernoulli)
dispatched for Bernoulli Distributions
FOR BINARY CLASSIFICATION MODELS.\
Given a calibration dataset ``(x_t, y_t)`` for ``i ∈ {1,...,T}`` let ``p_t= H(x_t)∈[0,1]`` be the forecasted probability. \
We group the ``p_t`` into intervals ``I_j`` for ``j= 1,2,...,m`` that form a partition of [0,1]. 
The function computes the observed average ``p_j= T^-1_j ∑_{t:p_t ∈ I_j} y_j`` in each interval ``I_j``.  \
Source: [Kuleshov, Fenner, Ermon 2018](https://arxiv.org/abs/1807.00263)

Inputs: \
    - `y_binary`: the array of outputs ``y_t`` numerically coded: 1 for the target class, 0 for the null class. \
    - `distributions`: an array of Bernoulli distributions \
    - `n_bins`: number of equally spaced bins to use.

Outputs: \
    - `num_p_per_interval`: array with the number of probabilities falling within interval. \
    - `emp_avg`: array with the observed empirical average per interval. \
    - `bin_centers`: array with the centers of the bins. 

"""
function empirical_frequency_binary_classification(
    y_binary, distributions::Vector{Bernoulli{Float64}}; n_bins::Int=20
)
    if n_bins <= 0
        throw(ArgumentError("n_bins must be a positive integer"))
    elseif !all(x -> x == 0 || x == 1, y_binary)
        throw(ArgumentError("y_binary must be an array of 0 and 1"))
    end
    #intervals boundaries
    n_edges = n_bins + 1
    int_bds = collect(range(0; stop=1, length=n_edges))
    #bin centers
    bin_centers = [(int_bds[i] + int_bds[i + 1]) / 2 for i in 1:(length(int_bds) - 1)]
    #initialize list for empirical averages per interval 
    emp_avg = []
    #initialize list for predicted averages per interval
    pred_avg = []
    # initialize list of number of probabilities falling within each intervals
    num_p_per_interval = []
    #list of the predicted probabilities for the target class
    class_probs = mean.(distributions)
    # iterate over the bins
    for j in 1:n_bins
        push!(num_p_per_interval, sum(int_bds[j] .< class_probs .<= int_bds[j + 1]))
        if num_p_per_interval[j] == 0
            push!(emp_avg, 0)
            push!(pred_avg, bin_centers[j])

        else
            # find the indices fo all istances for which class_probs fall withing the j-th interval
            indices = findall(x -> int_bds[j] < x <= int_bds[j + 1], class_probs)
            #compute the empirical average and saved it in emp_avg in the j-th position
            push!(emp_avg, 1 / num_p_per_interval[j] * sum(y_binary[indices]))
            #TO DO: maybe substitute to bin_Centers?
            push!(pred_avg, 1 / num_p_per_interval[j] * sum(class_probs[indices]))
        end
    end
    #return the tuple
    return (num_p_per_interval, emp_avg, bin_centers)
end




function extract_mean_and_variance(distr::Vector{Normal{Float64}})

    means= mean.(distr)
    variances= var.(distr)

    return means, variances

end

function sigma_scaling(y_pred::Vector{Normal{Float64}}, y_cal::Vector{Float64})

    lenght_y_cal= length(y_cal)


    means, variances= extract_mean_and_variance(y_pred)


    sigma = sqrt( 1 / lenght_y_cal *  sum(  norm.( y_cal .- means) ./variances   ) )


    return sigma


end

function sigma_scaling(la, x_cal::Vector{Float64}, y_cal::Vector{Float64})

    lenght_y_cal= length(y_cal)


    _, means, variances= glm_predictive_distribution(la, x_cal)


    sigma = sqrt( 1 / lenght_y_cal *  sum(  norm.( y_cal .- means) ./variances   ) )


    return sigma


end