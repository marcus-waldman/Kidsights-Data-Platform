# Skewness-Penalized Authenticity Screening Model

**RECOMMENDED MODEL:** `authenticity_glmm_beta_sumprior_stable.stan`

## Overview

The skewness-penalized model extends the base 2D IRT authenticity screening approach by simultaneously estimating item parameters, person effects, and participant weights while enforcing symmetric response patterns among weighted participants.

This document describes the **stabilized version** with logit-scale parameterization, which eliminates gradient explosion issues present in earlier prototypes.

## Core Idea

**Authentic participants** should exhibit symmetric distributions of item-level log-likelihoods when evaluated under a well-fitting IRT model. **Inauthentic participants** (e.g., random responders, pattern responders) create systematic negative skew because their responses are consistently less probable under the model.

Rather than using a two-stage approach (fit model → identify outliers → reweight), this model **jointly optimizes** all parameters with a penalty that encourages symmetry in the distribution of person-specific fit statistics.

## Key Components

### 1. Participant Weights (Logit-Scale Parameterization)

Each participant receives a weight `w[i] ∈ (0,1)` derived from a logit-scale parameter:

- **Parameters**: `logitwgt[i]` (unconstrained, -∞ to +∞)
- **Transformation**: `w[i] = inv_logit(logitwgt[i])`
- **Mixture Prior**: `0.5 × N(-2, 2) + 0.5 × N(2, 2)` on logit scale
  - Component 1: inv_logit(-2) ≈ 0.12 (favor exclusion)
  - Component 2: inv_logit(2) ≈ 0.88 (favor inclusion)
  - Creates **bimodal distribution**: clear include/exclude decision

**Why logit parameterization?**
- Eliminates hard boundaries at 0 and 1 (no optimizer walls)
- Smooth gradients everywhere via inv_logit() transformation
- Parameters near boundaries (high |logitwgt|) = clear decisions (good!)

### 1b. Sum Prior (Prevents Degeneracy)

To prevent all weights collapsing to near-zero, a Normal prior constrains the sum:

- **Prior**: `sum(w) ~ N(N, σ_sum_w)`
- **Rationale**: Without constraint, mixture prior alone allows pathological solutions
- **Behavior**: Acts like a "spring" pulling sum(w) back toward N
- **Tuning**: σ_sum_w controls tolerance for down-weighting (see Hyperparameters below)

**Why Normal (not Laplace)?**
- **Normal gradient**: Grows linearly with deviation `-(sum(w) - N) / σ²`
  - Fights back **harder** as sum(w) drifts further from N
  - Prevents degeneracy by increasing resistance to weight collapse
- **Laplace gradient**: Constant `±1/σ` regardless of distance
  - Equal resistance whether sum(w) = N-10 or sum(w) = N-100
  - Allows degeneracy when likelihood strongly prefers sparse solutions
- **Empirical testing**: Both were tested; Normal prevents weight collapse better

### 2. Within-Person t-Statistics

For each participant, compute a precision-weighted t-statistic:

- **Mean**: Average log-likelihood per item for participant i
- **SD**: Within-person standard deviation across items
- **t-statistic**: Standardized deviation from population mean, adjusted for number of items via √M

This accounts for the fact that participants with more items provide more precise estimates.

### 3. Weighted Skewness (with Soft-Clipped t-Statistics)

All distributional statistics (mean, variance, skewness) use **weighted versions** that down-weight excluded participants:

- Participants with high weights contribute fully to skewness calculation
- Participants with low weights barely affect the distribution
- Creates feedback loop: down-weighting outliers reduces skewness

**Stability improvement**: t-statistics are **soft-clipped** using tanh before cubing:
- `t_soft[i] = 10 × tanh(t[i] / 10)`
- Prevents extreme outliers (|t| > 10) from creating gradient explosions when cubed
- For |t| < 5: barely changes values (tanh ≈ linear)
- For |t| >> 10: asymptotically caps at ±10 (saturates smoothly)
- Critical for LBFGS optimization stability

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
2. **Identifiability**: Sum prior + mixture prior prevent unidentifiable solutions
3. **Efficiency**: Single-stage estimation avoids iterative two-stage procedures
4. **Precision Weighting**: Accounts for varying information content across participants
5. **Gradient Stability**: Logit parameterization + soft-clipping ensure smooth optimization

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

### Fixed Hyperparameters

**lambda_skew** (Skewness penalty strength):
- **Recommended**: 1.0 (equal weight to likelihood)
- Empirically validated as stable across different datasets
- Increase if too few participants excluded (stronger symmetry enforcement)
- Decrease if too many excluded (weaker penalty, more data-driven)

### Tuning Required via Cross-Validation

**sigma_sum_w** (Normal sum prior scale):
- **Tuning range**: 0.5 to 2.0
- **Small values (0.5-1.0)**: Tight constraint, strong preference for sum ≈ N
  - Use when expecting few inauthentic participants (<5%)
  - Prevents aggressive down-weighting
- **Medium values (1.0-1.5)**: Moderate tolerance, allows ~5-10% deviation
  - Recommended starting point for most applications
- **Large values (1.5-2.0)**: Weak constraint, allows substantial down-weighting
  - Use when expecting many inauthentic participants (>10%)
  - Provides flexibility for sparsity

**Cross-validation strategy**:
1. Fit models with σ_sum_w ∈ {0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0}
2. Compute LOOCV log-posterior or WAIC for each
3. Select σ_sum_w that maximizes predictive accuracy
4. Validate selected value produces sensible exclusion rate (e.g., 5-15%)

## Model Outputs

After convergence, the model provides:

- **Weights (w)**: Participant-specific inclusion weights
  - **Not** constrained to sum = N (regularized toward N via sum prior)
  - Mean weight ≈ 1 but can deviate based on σ_sum_w
  - Individual weights ∈ (0, 1) via inv_logit transformation
- **Skewness diagnostics**:
  - Weighted skewness (using soft-clipped t-statistics)
  - Z-score: standardized skewness ~ N(0,1) under null
  - N_eff: Kish effective sample size accounting for weight heterogeneity
  - Sum diagnostics: sum(w), deviation from N, percentage change
- **Classification**: Count of excluded (w < 0.1), included (w > 0.9), uncertain (0.1 ≤ w ≤ 0.9)
- **Item parameters**: Robust estimates under down-weighted outliers
- **Person effects**: 2D eta estimates for all participants (independent dimensions)

## Comparison to LOOCV Approach

| Aspect | LOOCV (Current) | Skewness-Penalized (Stable) |
|--------|-----------------|---------------------------|
| **Stages** | Two-stage (fit → weight) | Single-stage (joint) |
| **Computation** | ~18 min (N models) | TBD (~8K parameters, needs benchmarking) |
| **Weights** | ATT propensity weights | Logit-scale probabilistic inclusion |
| **Threshold** | Fixed Cook's D quantiles | Data-adaptive via skewness penalty |
| **Item parameters** | Unaffected by weights | Jointly estimated (robust to outliers) |
| **Stability** | Deterministic (LOOCV) | Gradient-stable (soft-clipping + logit param) |
| **Hyperparameters** | Influence threshold (fixed) | λ_skew=1 (fixed), σ_sum_w (CV-tuned) |

Both approaches are valid; the skewness-penalized model offers theoretical elegance and single-stage estimation at the cost of additional hyperparameter tuning.

---

## Stability Features (v2 - Stabilized Model)

The stabilized version (`authenticity_glmm_beta_sumprior_stable.stan`) includes three critical improvements over earlier prototypes:

1. **Logit-scale parameterization**: Eliminates hard boundaries, smooth gradients everywhere
2. **Soft-clipped t-statistics**: Prevents gradient explosion from extreme outliers (tanh before cubing)
3. **Soft boundaries throughout**: Uses `var + ε` instead of `fmax(var, ε)` for all safeguards

**Why this matters**: Earlier versions experienced gradient explosions during optimization. The stabilized model compiles cleanly and shows promising convergence behavior.

---

**Model file**: `authenticity_glmm_beta_sumprior_stable.stan` (recommended)
**Alternative prototypes**: See `models/` directory for 7 additional experimental variants
**Last updated**: November 2025 (R&D phase)
