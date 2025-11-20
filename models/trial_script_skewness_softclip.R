main_model <- rstan::stan_model("models/authenticity_glmm_softclip_sumprior.stan")
stan_data_full <- readRDS("data/temp/stan_data_authentic.rds")
stan_data_full$lambda_skew = 1
stan_data_full$lambda_wgt = .1
stan_data_full$sigma_sum_softwgt = .1

fit_full <- rstan::optimizing(
  object = main_model,
  data = stan_data_full,
  init = fit_full,
  iter = 10000,
  algorithm = "LBFGS",
  verbose = TRUE,
  refresh = 20,
  history_size = 50,
  tol_obj = 1e-12,
  tol_rel_obj = 1,
  tol_grad = 1e-8,
  tol_rel_grad = 1e3,
  tol_param = 1e-8
)

A# Extract weights from optimization results
N <- stan_data_full$N
w_raw_indices <- paste0("softwgt[", 1:N, "]")
w <- fit_full$par[w_raw_indices]


library(tidyverse)
ggplot(data.frame(wgt = w), aes(wgt)) + stat_ecdf(geom= "point")

# Summary statistics
cat("\n")
cat("================================================================================\n")
cat("  WEIGHT DIAGNOSTICS\n")
cat("================================================================================\n")
cat("\n")
cat(sprintf("N participants: %d\n", N))
cat(sprintf("Sum of weights: %.2f (should be %d)\n", sum(w), N))
cat(sprintf("Mean weight: %.4f (should be ~1.0)\n", mean(w)))
cat(sprintf("Min weight: %.4f\n", min(w)))
cat(sprintf("Max weight: %.4f\n", max(w)))
cat(sprintf("SD of weights: %.4f\n", sd(w)))
cat("\n")
cat(sprintf("Excluded (w < 0.1): %d participants (%.1f%%)\n",
            sum(w < 0.1), 100 * sum(w < 0.1) / N))
cat(sprintf("Included (w > 0.9): %d participants (%.1f%%)\n",
            sum(w > 0.9), 100 * sum(w > 0.9) / N))
cat(sprintf("Uncertain (0.1 <= w <= 0.9): %d participants (%.1f%%)\n",
            sum(w >= 0.1 & w <= 0.9), 100 * sum(w >= 0.1 & w <= 0.9) / N))
cat("\n")

# Histogram of weights
hist(w,
     breaks = 50,
     main = "Distribution of Participant Weights",
     xlab = "Weight (sum = N, mean = 1)",
     ylab = "Frequency",
     col = "steelblue",
     border = "white")
abline(v = 0.1, col = "red", lwd = 2, lty = 2)
abline(v = 0.9, col = "red", lwd = 2, lty = 2)
abline(v = 1.0, col = "darkgreen", lwd = 2, lty = 2)
legend("topright",
       legend = c("w = 1.0 (neutral)", "w = 0.1 (exclude)", "w = 0.9 (include)"),
       col = c("darkgreen", "red", "red"),
       lwd = 2,
       lty = 2)
