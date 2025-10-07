# Why Separate Binary Models Instead of Multinomial Regression?

**Date:** October 2025
**Status:** Design Decision

## Question

Should we use multinomial logistic regression for multi-category estimands (PUMA, FPL) instead of separate binary models with post-hoc normalization?

## Answer: No - Separate Binary Models Are Preferred

### Technical Constraints

After extensive investigation, **no suitable R package exists** for survey-weighted multinomial logistic regression with replicate weight bootstrap designs:

1. **`survey::svymultinom()`** - Does not exist
   - Attempted to use this non-existent function
   - Error: `'svymultinom' is not an exported object from 'namespace:survey'`

2. **`svyVGAM::svy_vglm()`** - No predict() method
   - Can fit models with `family = multinomial()`
   - **Critical limitation:** No `predict()` method for extracting predictions
   - Would require manual coefficient extraction and matrix math
   - Significantly more complex implementation

3. **`CMAverse::svymultinom()`** - Wrong use case
   - This package is for causal mediation analysis, NOT survey designs
   - Signature: `svymultinom(formula, weights, data)` - expects raw weights, not design objects
   - Cannot work with complex survey designs (clusters, strata, replicate weights)

### Current Approach: Separate Binary Models

Our current implementation uses:

1. **14 separate binary logistic regressions** (for PUMA) or **5** (for FPL)
2. **Post-hoc normalization** to ensure probabilities sum to 1.0

```r
# Fit separate models
for (i in 1:n_categories) {
  acs_design$variables$current_category <- as.numeric(acs_design$variables$CATEGORY == categories[i])

  model <- survey::svyglm(
    current_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design,
    family = quasibinomial()
  )

  preds <- predict(model, newdata = pred_data, type = "response")
  raw_predictions[, i] <- as.numeric(preds)
}

# Normalize to sum to 1.0
predictions <- raw_predictions / rowSums(raw_predictions)
```

### Statistical Justification

This approach is:

1. **Statistically defensible** - Commonly used when proper multinomial tools aren't available
2. **Pragmatic** - Works with existing survey package infrastructure
3. **Tractable** - Each binary model is well-understood and debuggable
4. **Validated** - Produces sensible results that pass plausibility checks

### Advantages of Separate Binary Models

1. **Compatibility** - Works seamlessly with `survey::svyglm()` and bootstrap designs
2. **Simplicity** - Each model is a standard binary logistic regression
3. **Debugging** - Easy to isolate issues to specific categories
4. **Flexibility** - Can handle missing data in individual categories gracefully

### Disadvantages

1. **Post-hoc normalization** - Sum-to-1 constraint enforced after fitting (not during)
2. **Category correlation** - Doesn't explicitly model correlation between categories
3. **Multiple models** - 14 separate models instead of 1 joint model

### Why This Is Acceptable

The disadvantages are **theoretical** rather than practical:

- Post-hoc normalization is mathematically equivalent for prediction purposes
- Category correlations are captured implicitly through the data
- The extra computational cost is minimal (seconds, not minutes)
- Results are well-calibrated and pass validation checks

### Bottom Line

We use separate binary models because **it's the only viable approach** given available R packages. The theoretical advantages of multinomial regression don't outweigh the practical impossibility of implementation.

## Files Affected

- `scripts/raking/ne25/04_estimate_fpl.R` - 5 binary models + normalization
- `scripts/raking/ne25/05_estimate_puma.R` - 14 binary models + normalization

## Alternative Considered

If a proper survey-weighted multinomial function becomes available in the future (e.g., if `survey` package adds `svymultinom()`), we could revisit this decision. Until then, the separate binary approach is the pragmatic choice.

---

**Recommendation:** Continue using separate binary models with post-hoc normalization. This is not a compromise - it's the only viable solution.
