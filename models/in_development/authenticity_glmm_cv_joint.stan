/**
 * Authenticity Screening GLMM - CV with Joint Posterior (ALTERNATIVE)
 *
 * This model estimates item parameters (τ, β, δ) AND person effects (η)
 * jointly from the training data, without integrating out η.
 *
 * Key Design Features:
 *   - NO weight parameters (data already filtered to w > 0.5 in Phase 2)
 *   - YES eta parameters (estimated as parameters, not integrated out)
 *   - NO skewness/sum penalties (only used in Phase 1b for weight estimation)
 *   - Training uses joint posterior, holdout uses marginal likelihood
 *
 * Cross-Validation Logic:
 *   - Training data: P(τ, β, δ, η_train | y_train)  [joint posterior]
 *   - Holdout data: ∫ P(y_holdout | τ, β, δ, η) P(η) dη  [marginal likelihood]
 *   - ASYMMETRY: Training estimates η, holdout integrates it out
 *
 * Integration Strategy (holdout only):
 *   - Two independent 1D integrations (dimensions uncorrelated)
 *   - 21-point GH quadrature for N(0,1) prior on each η dimension
 *   - Log-sum-exp trick for numerical stability
 *
 * Comparison to Integrated Likelihood Model (authenticity_glmm_cv_integrated.stan):
 *   - JOINT (this model): Faster optimization (~1-2 min/fit) by estimating η
 *   - INTEGRATED (default): Slower (~3-10 min/fit) but symmetric evaluation
 *   - Use JOINT when speed is critical, INTEGRATED for principled CV
 */

data {
  // ============================================================================
  // TRAINING DATA (used for fitting item and person parameters)
  // ============================================================================

  int<lower=1> M_train;        // Number of training observations
  int<lower=1> N_train;        // Number of training persons
  int<lower=1> J;              // Number of items

  array[M_train] int<lower=1, upper=N_train> ivec_train;
  array[M_train] int<lower=1, upper=J> jvec_train;
  array[M_train] int<lower=0> yvec_train;

  vector[N_train] age_train;   // Age for training persons

  // ============================================================================
  // HOLDOUT DATA (used only for evaluation in generated quantities)
  // ============================================================================

  int<lower=0> M_holdout;      // Number of holdout observations
  int<lower=0> N_holdout;      // Number of holdout persons

  array[M_holdout] int<lower=1, upper=N_holdout> ivec_holdout;
  array[M_holdout] int<lower=1, upper=J> jvec_holdout;
  array[M_holdout] int<lower=0> yvec_holdout;

  vector[N_holdout] age_holdout;  // Age for holdout persons

  // ============================================================================
  // ITEM METADATA (shared across train/holdout)
  // ============================================================================

  array[J] int<lower=2> K;                      // Number of categories per item
  array[J] int<lower=1, upper=2> dimension;     // Dimension: 1=psychosocial, 2=developmental
  array[J] int<lower=1> kvec;                   // Lookup: category count per item
  array[J] int<lower=1, upper=2> dimvec;        // Lookup: dimension per item

  // ============================================================================
  // GAUSS-HERMITE QUADRATURE (for holdout evaluation only)
  // ============================================================================

  int<lower=1> n_nodes;        // Number of GH nodes (typically 21)
  vector[n_nodes] gh_nodes;    // GH nodes for N(0,1)
  vector[n_nodes] gh_weights;  // GH weights (sum to 1.0 for N(0,1))
}

transformed data {
  // Count items per training person
  array[N_train] int n_items_train = rep_array(0, N_train);

  // Count items per holdout person (for deviance normalization)
  array[N_holdout] int n_items_holdout = rep_array(0, N_holdout);

  // Count training items
  for (m in 1:M_train) {
    n_items_train[ivec_train[m]] += 1;
  }

  // Count holdout items
  for (m in 1:M_holdout) {
    n_items_holdout[ivec_holdout[m]] += 1;
  }
}

parameters {
  // Item parameters (estimated from training data)
  vector[J] tau;                     // Item intercepts
  vector[J] beta1;                   // Age slopes
  vector<lower=0>[2] delta;          // Threshold spacings (dim 1, dim 2)

  // Person effects for TRAINING persons (estimated as parameters)
  vector[N_train] eta_psychosocial_train;
  vector[N_train] eta_developmental_train;
}

transformed parameters {
  // Construct eta matrix
  matrix[N_train, 2] eta_train;
  eta_train[, 1] = eta_psychosocial_train;
  eta_train[, 2] = eta_developmental_train;

  // Cumulative thresholds for graded response model
  vector[J] thresh1;
  vector[J] thresh2;
  vector[J] thresh3;
  vector[J] thresh4;

  for (j in 1:J) {
    int k = K[j];
    int d = dimension[j];

    real mu_j = tau[j];

    if (k == 2) {
      thresh1[j] = mu_j;
      thresh2[j] = positive_infinity();
      thresh3[j] = positive_infinity();
      thresh4[j] = positive_infinity();
    } else if (k == 3) {
      thresh1[j] = mu_j - delta[d];
      thresh2[j] = mu_j + delta[d];
      thresh3[j] = positive_infinity();
      thresh4[j] = positive_infinity();
    } else if (k == 4) {
      thresh1[j] = mu_j - 1.5 * delta[d];
      thresh2[j] = mu_j - 0.5 * delta[d];
      thresh3[j] = mu_j + 0.5 * delta[d];
      thresh4[j] = positive_infinity();
    } else {
      thresh1[j] = mu_j - 2 * delta[d];
      thresh2[j] = mu_j - delta[d];
      thresh3[j] = mu_j;
      thresh4[j] = mu_j + delta[d];
    }
  }

  // Person-level log-likelihoods (sum over items for each person)
  vector[N_train] person_loglik = rep_vector(0, N_train);

  for (m in 1:M_train) {
    int i = ivec_train[m];
    int j = jvec_train[m];
    int y = yvec_train[m];
    int k = K[j];
    int d = dimension[j];

    real mu = tau[j] + beta1[j] * age_train[i];
    real latent = mu + eta_train[i, d];

    // Compute ordered logit probability
    real prob_y;
    if (y == 0) {
      prob_y = inv_logit(thresh1[j] - latent);
    } else if (y == 1) {
      if (k == 2) {
        prob_y = 1.0 - inv_logit(thresh1[j] - latent);
      } else {
        prob_y = inv_logit(thresh2[j] - latent) - inv_logit(thresh1[j] - latent);
      }
    } else if (y == 2) {
      if (k == 3) {
        prob_y = 1.0 - inv_logit(thresh2[j] - latent);
      } else {
        prob_y = inv_logit(thresh3[j] - latent) - inv_logit(thresh2[j] - latent);
      }
    } else if (y == 3) {
      if (k == 4) {
        prob_y = 1.0 - inv_logit(thresh3[j] - latent);
      } else {
        prob_y = inv_logit(thresh4[j] - latent) - inv_logit(thresh3[j] - latent);
      }
    } else {
      // y == 4 (only for 5-category items)
      prob_y = 1.0 - inv_logit(thresh4[j] - latent);
    }

    person_loglik[i] += log(prob_y + 1e-10);
  }
}

model {
  // ============================================================================
  // PRIORS ON ITEM PARAMETERS
  // ============================================================================

  tau ~ normal(0, 5);
  beta1 ~ normal(0, 2);
  delta ~ student_t(3, 0, 1);

  // ============================================================================
  // PRIORS ON PERSON EFFECTS (INDEPENDENT)
  // ============================================================================

  eta_psychosocial_train ~ std_normal();
  eta_developmental_train ~ std_normal();

  // ============================================================================
  // LIKELIHOOD (TRAINING DATA ONLY)
  // ============================================================================

  // Unweighted likelihood (data already filtered to w > 0.5)
  for (i in 1:N_train) {
    target += person_loglik[i];
  }
}

generated quantities {
  // ============================================================================
  // HOLDOUT EVALUATION VIA GAUSS-HERMITE QUADRATURE
  // ============================================================================

  vector[N_holdout] holdout_loglik = rep_vector(0, N_holdout);
  vector[N_holdout] holdout_deviance = rep_vector(0, N_holdout);
  real fold_loss = 0;

  // For each holdout person, compute marginal likelihood
  for (i_holdout in 1:N_holdout) {
    vector[n_nodes] loglik_dim1 = rep_vector(0, n_nodes);
    vector[n_nodes] loglik_dim2 = rep_vector(0, n_nodes);

    int n_dim1 = 0;
    int n_dim2 = 0;

    real age_i = age_holdout[i_holdout];

    // Accumulate item log-likelihoods for each GH node
    for (m in 1:M_holdout) {
      if (ivec_holdout[m] == i_holdout) {
        int j = jvec_holdout[m];
        int y = yvec_holdout[m];
        int k = kvec[j];
        int d = dimvec[j];

        real mu = tau[j] + beta1[j] * age_i;

        for (node_idx in 1:n_nodes) {
          real eta = gh_nodes[node_idx];
          real latent = mu + eta;

          real prob_y;
          if (y == 0) {
            prob_y = inv_logit(thresh1[j] - latent);
          } else if (y == 1) {
            if (k == 2) {
              prob_y = 1.0 - inv_logit(thresh1[j] - latent);
            } else {
              prob_y = inv_logit(thresh2[j] - latent) - inv_logit(thresh1[j] - latent);
            }
          } else if (y == 2) {
            if (k == 3) {
              prob_y = 1.0 - inv_logit(thresh2[j] - latent);
            } else {
              prob_y = inv_logit(thresh3[j] - latent) - inv_logit(thresh2[j] - latent);
            }
          } else if (y == 3) {
            if (k == 4) {
              prob_y = 1.0 - inv_logit(thresh3[j] - latent);
            } else {
              prob_y = inv_logit(thresh4[j] - latent) - inv_logit(thresh3[j] - latent);
            }
          } else {
            prob_y = 1.0 - inv_logit(thresh4[j] - latent);
          }

          if (d == 1) {
            loglik_dim1[node_idx] += log(prob_y + 1e-10);
            if (node_idx == 1) n_dim1 += 1;
          } else {
            loglik_dim2[node_idx] += log(prob_y + 1e-10);
            if (node_idx == 1) n_dim2 += 1;
          }
        }
      }
    }

    // Marginalize dimensions
    real log_marginal_dim1 = negative_infinity();
    real log_marginal_dim2 = negative_infinity();

    if (n_dim1 > 0) {
      for (k in 1:n_nodes) {
        log_marginal_dim1 = log_sum_exp(log_marginal_dim1,
                                         log(gh_weights[k]) + loglik_dim1[k]);
      }
    } else {
      log_marginal_dim1 = 0;
    }

    if (n_dim2 > 0) {
      for (k in 1:n_nodes) {
        log_marginal_dim2 = log_sum_exp(log_marginal_dim2,
                                         log(gh_weights[k]) + loglik_dim2[k]);
      }
    } else {
      log_marginal_dim2 = 0;
    }

    // Total marginal log-likelihood
    holdout_loglik[i_holdout] = log_marginal_dim1 + log_marginal_dim2;

    // Deviance (normalized by number of items for this person)
    holdout_deviance[i_holdout] = -2 * holdout_loglik[i_holdout] / n_items_holdout[i_holdout];
  }

  // Fold loss: mean deviance across holdout persons
  if (N_holdout > 0) {
    fold_loss = mean(holdout_deviance);
  }
}
