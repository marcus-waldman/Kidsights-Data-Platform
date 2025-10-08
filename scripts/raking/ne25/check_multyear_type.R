# Check MULTYEAR variable type
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

cat("MULTYEAR variable info:\n")
cat("  Class:", class(acs_design$variables$MULTYEAR), "\n")
cat("  Type:", typeof(acs_design$variables$MULTYEAR), "\n")
cat("  Is factor:", is.factor(acs_design$variables$MULTYEAR), "\n")
cat("  Is numeric:", is.numeric(acs_design$variables$MULTYEAR), "\n")
cat("  Values:", sort(unique(acs_design$variables$MULTYEAR)), "\n")
