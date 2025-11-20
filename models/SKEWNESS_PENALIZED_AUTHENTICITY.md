# Skewness-Penalized Authenticity Screening Model

## Overview

The skewness-penalized model extends the base 2D IRT authenticity screening approach by simultaneously estimating item parameters, person effects, and participant weights while enforcing symmetric response patterns among weighted participants.

## Core Idea

**Authentic participants** should exhibit symmetric distributions of item-level log-likelihoods when evaluated under a well-fitting IRT model. **Inauthentic participants** (e.g., random responders, pattern responders) create systematic negative skew because their responses are consistently less probable under the model.

Rather than using a two-stage approach (fit model → identify outliers → reweight), this model **jointly optimizes** all parameters with a penalty that encourages symmetry in the distribution of person-specific fit statistics.

## Key Components

### 1. Participant Weights

Each participant receives a weight `w[i]` on a simplex (constrained to sum to N). The simplex constraint prevents degeneracy where all weights collapse to zero. Weights are governed by a Dirichlet prior:

- **λ < 1**: Encourages sparse solutions (most weights ≈ 1, outliers → 0)
- **λ = 1**: Non-informative (uniform over simplex)
- **λ > 1**: Discourages extreme weights (all weights similar)

### 2. Within-Person t-Statistics

For each participant, compute a precision-weighted t-statistic:

- **Mean**: Average log-likelihood per item for participant i
- **SD**: Within-person standard deviation across items
- **t-statistic**: Standardized deviation from population mean, adjusted for number of items via √M

This accounts for the fact that participants with more items provide more precise estimates.

### 3. Weighted Skewness

All distributional statistics (mean, variance, skewness) use **weighted versions** that down-weight excluded participants:

- Participants with high weights contribute fully to skewness calculation
- Participants with low weights barely affect the distribution
- Creates feedback loop: down-weighting outliers reduces skewness

### 4. Effective Sample Size Correction

The **Kish effective sample size** adjusts the standard error of skewness for weight heterogeneity:

- When weights are uniform: N_eff = N (full precision)
- When weights vary: N_eff < N (inflated variance)
- Prevents over-confidence in skewness estimates when many participants are down-weighted

### 5. Probabilistic Penalty

Under normality, sample skewness has variance ≈ 6/N_eff. The standardized skewness therefore follows N(0,1) under the null. The penalty term treats this as a prior:

- Penalizes deviations from zero skewness
- Strength controlled by λ_skew hyperparameter
- λ_skew = 1 means "skewness prior has equal weight to likelihood"

## Why This Approach Makes Sense

### Theoretical Justification

1. **Bayesian Coherence**: All components are proper priors with probabilistic interpretation
2. **Identifiability**: Simplex constraint prevents unidentifiable solutions
3. **Efficiency**: Single-stage estimation avoids iterative two-stage procedures
4. **Precision Weighting**: Accounts for varying information content across participants

### Practical Advantages

1. **Automatic Detection**: Model identifies inauthentic participants without pre-specified thresholds
2. **Uncertainty Quantification**: Weights represent probability of authenticity (soft classification)
3. **Robust Calibration**: Item parameters estimated under down-weighted outliers are more robust
4. **Interpretable Output**: Weights near 0 → exclude, weights near 1 → include

### Statistical Properties

- **Asymmetric Detection**: Specifically targets left-skew (poor fit), not right-skew
- **Adaptive Thresholds**: Cutoff emerges from data rather than fixed at -2 SD
- **Feedback Stabilization**: Weights and skewness reach equilibrium where down-weighting outliers restores symmetry

## Hyperparameter Recommendations

**lambda_wgt** (Dirichlet concentration):
- Start with 0.5 (moderate sparsity, Jeffreys-like prior)
- Decrease to 0.1 for aggressive exclusion if many inauthentic participants expected
- Increase to 1.0 for conservative approach (uniform prior)

**lambda_skew** (Skewness penalty strength):
- Start with 1.0 (equal weight to likelihood)
- Increase if too few participants excluded (stronger symmetry enforcement)
- Decrease if too many excluded (weaker penalty, more data-driven)

## Model Outputs

After convergence, the model provides:

- **Weights (w)**: Participant-specific inclusion weights (sum = N, mean = 1)
- **Skewness diagnostics**: Weighted skewness, z-score, N_eff
- **Classification**: Count of excluded (w < 0.1), included (w > 0.9), uncertain (0.1 ≤ w ≤ 0.9)
- **Item parameters**: Robust estimates under down-weighted outliers
- **Person effects**: 2D eta estimates for all participants

## Comparison to LOOCV Approach

| Aspect | LOOCV (Current) | Skewness-Penalized |
|--------|-----------------|-------------------|
| **Stages** | Two-stage (fit → weight) | Single-stage (joint) |
| **Computation** | ~18 min (N models) | Unknown (8K parameters) |
| **Weights** | ATT propensity weights | Probabilistic inclusion |
| **Threshold** | Fixed quintiles | Data-adaptive via penalty |
| **Item parameters** | Unaffected by weights | Robust to outliers |

Both approaches are valid; the skewness-penalized model offers theoretical elegance at the cost of computational complexity.

---

**Model file**: `authenticity_glmm_skewpenalty.stan`
**Last updated**: January 2025
