# IRT Parameter Constraints Specification Guide

**Version:** 1.0
**Last Updated:** January 2025
**Status:** Production Reference

---

## Purpose

This guide provides comprehensive documentation for specifying IRT parameter constraints in the Kidsights codebook. These constraints are used during **item calibration** to:

1. Link items with identical content across studies (complete equality)
2. Share discrimination parameters while allowing different thresholds (slope-only equality)
3. Enforce developmental ordering of milestones (threshold ordering)
4. Interpolate thresholds between developmental anchors (simplex constraints)
5. Implement 1-PL/Rasch models (automatic for unconstrained items)

---

## Constraint Types Overview

| Constraint Type | Codebook Syntax | Parameters Affected | Use Case |
|----------------|-----------------|-------------------|----------|
| **Complete Equality** | `"Constrain all to ITEM"` | All (a, b1, b2, ...) | Identical items across studies |
| **Slope-Only Equality** | `"Constrain slope to ITEM"` | Discrimination (a) only | Same construct, different difficulty |
| **Threshold Ordering** | `"Constrain tau$N to be greater than ITEM$N"` | Specific threshold (bN) | Developmental ordering |
| **Simplex Constraints** | `"Constrain tau$N to be a simplex between ITEM1$N and ITEM2$N"` | Specific threshold (bN) | Linear interpolation |
| **1-PL/Rasch** | Automatic for unconstrained items | Discrimination (a) | Equal discrimination across items |

---

## Constraint Type 1: Complete Equality

### Syntax
```
"Constrain all to [REFERENCE_ITEM]"
```

### Effect
- Share **ALL** parameters with reference item:
  - Discrimination parameter (a)
  - All threshold parameters (b1, b2, b3, ...)
- Constrained items essentially become duplicates of reference item

### When to Use
- Items with **identical wording** across studies
- Items measuring the **exact same behavior** at the **same difficulty level**
- Linking items for cross-study equating

### Codebook Example
```json
{
  "id": 2,
  "lexicons": {
    "equate": "AA104",
    "ne25": "AA104",
    "ne22": "AA104_22"
  },
  "psychometric": {
    "param_constraints": "Constrain all to AA102"
  }
}
```

### Generated Mplus Syntax
```mplus
! MODEL section
kidsights BY AA102* (a_1);
kidsights BY AA104* (a_1);

[AA102$1] (t1_1);
[AA102$2] (t2_1);
[AA104$1] (t1_1);
[AA104$2] (t2_1);
```

### Interpretation
- Both AA102 and AA104 share parameter labels `a_1`, `t1_1`, `t2_1`
- Mplus estimates **one set of parameters** for both items
- Reduces parameter count, increases statistical power

---

## Constraint Type 2: Slope-Only Equality

### Syntax
```
"Constrain slope to [REFERENCE_ITEM]"
```

### Effect
- Share **discrimination parameter (a)** with reference item
- Estimate **separate threshold parameters (b1, b2, ...)** for this item
- Items measure same construct with equal strength but different difficulty

### When to Use
- Items measuring the **same domain** (e.g., both measure fine motor skills)
- Different **developmental difficulty** (e.g., "pick up small object" vs "stack blocks")
- Want to constrain discrimination but allow different thresholds

### Codebook Example
```json
{
  "id": 5,
  "lexicons": {
    "equate": "AA110"
  },
  "psychometric": {
    "param_constraints": "Constrain slope to AA102"
  }
}
```

### Generated Mplus Syntax
```mplus
! MODEL section
kidsights BY AA102* (a_1);
kidsights BY AA110* (a_1);

[AA102$1] (t1_1);
[AA102$2] (t2_1);
[AA110$1] (t1_5);
[AA110$2] (t2_5);
```

### Interpretation
- AA110 shares discrimination `a_1` with AA102
- AA110 has **unique** thresholds `t1_5`, `t2_5`
- Same slope, different intercepts (parallel ICC curves)

---

## Constraint Type 3: Threshold Ordering

### Syntax
```
"Constrain tau$[N] to be greater than [REFERENCE_ITEM]$[N]"
"Constrain tau$[N] to be less than [REFERENCE_ITEM]$[N]"
```

### Effect
- Enforce **inequality constraint** on specific threshold parameter
- Threshold N of this item must be > or < threshold N of reference item
- Implements developmental ordering (e.g., "walks" > "stands")

### When to Use
- **Developmental milestones** with known ordering
- Enforce that harder skills have higher thresholds
- Prevent parameter estimation from violating developmental theory

### Codebook Example
```json
{
  "id": 8,
  "lexicons": {
    "equate": "GM015"
  },
  "domains": {
    "kidsights": {
      "value": "motor"
    }
  },
  "psychometric": {
    "param_constraints": "Constrain tau$1 to be greater than GM010$1"
  }
}
```

### Generated Mplus Syntax
```mplus
! MODEL section
kidsights BY GM010* (a_8);
kidsights BY GM015* (a_9);

[GM010$1] (t1_8);
[GM015$1] (t1_9);

! MODEL CONSTRAINT section
t1_9 > t1_8;  ! GM015$1 > GM010$1 (developmental ordering)
```

### Interpretation
- GM015 (later milestone) has higher threshold than GM010 (earlier milestone)
- Constraint enforces developmental sequence
- Prevents illogical parameter estimates

### Multiple Thresholds
You can constrain multiple thresholds with semicolon separation:
```json
"param_constraints": "Constrain tau$1 to be greater than GM010$1; Constrain tau$2 to be greater than GM010$2"
```

---

## Constraint Type 4: Simplex Constraints

### Syntax
```
"Constrain tau$[N] to be a simplex between [ITEM1]$[N] and [ITEM2]$[N]"
```

### Effect
- Threshold N is **linearly interpolated** between two anchor items
- Implements: `tau_N = (tau_ITEM1_N + tau_ITEM2_N) / 2`
- Creates smooth developmental progression

### When to Use
- Item is **developmentally intermediate** between two anchors
- Want to enforce smooth transitions in difficulty
- Reduce parameter count for similar items

### Codebook Example
```json
{
  "id": 12,
  "lexicons": {
    "equate": "GM025"
  },
  "psychometric": {
    "param_constraints": "Constrain tau$1 to be a simplex between GM020$1 and GM030$1"
  }
}
```

### Generated Mplus Syntax
```mplus
! MODEL section
kidsights BY GM020* (a_10);
kidsights BY GM025* (a_12);
kidsights BY GM030* (a_13);

[GM020$1] (t1_10);
[GM025$1] (t1_12);
[GM030$1] (t1_13);

! MODEL CONSTRAINT section
NEW (p1);
p1 = (t1_10 + t1_13) / 2;  ! Midpoint of GM020 and GM030
t1_12 = p1;  ! GM025 threshold equals midpoint
```

### Interpretation
- GM025 difficulty is **average** of GM020 and GM030
- Creates smooth developmental trajectory
- Reduces degrees of freedom (one fewer parameter to estimate)

---

## Constraint Type 5: 1-PL/Rasch Model

### Syntax
No explicit syntax required - **automatic for unconstrained items**

### Effect
- All items **without explicit constraints** get equal discrimination constraints
- Implements: `a_1 = a_2 = a_3 = ... = a_K`
- Reduces to 1-parameter logistic (1-PL) or Rasch model
- Bayesian N(1,1) priors on discrimination parameters for regularization

### When to Use
- Default behavior for most items
- Simplifies model (single discrimination parameter)
- Improves convergence with smaller samples

### Generated Mplus Syntax
```mplus
! MODEL section (all items share discrimination label)
kidsights BY AA102* (a_pool);
kidsights BY AA104* (a_pool);
kidsights BY AA105* (a_pool);

[AA102$1] (t1_1);
[AA102$2] (t2_1);
[AA104$1] (t1_2);
[AA104$2] (t2_2);

! MODEL CONSTRAINT section (equality constraints)
a_pool = a_1;
a_pool = a_2;
a_pool = a_3;

! MODEL PRIOR section (Bayesian regularization)
a_pool ~ N(1,1);
```

### Interpretation
- Single shared discrimination parameter `a_pool`
- Each item has unique thresholds
- N(1,1) prior prevents extreme parameter estimates

---

## Multiple Constraints

You can specify **multiple constraints** for a single item using semicolon (`;`) separation:

### Syntax
```
"Constrain [TYPE1]; Constrain [TYPE2]; Constrain [TYPE3]"
```

### Example
```json
{
  "id": 15,
  "lexicons": {
    "equate": "EL045"
  },
  "psychometric": {
    "param_constraints": "Constrain slope to EL040; Constrain tau$1 to be greater than EL040$1"
  }
}
```

### Generated Mplus Syntax
```mplus
! MODEL section
kidsights BY EL040* (a_14);
kidsights BY EL045* (a_14);  ! Shared slope

[EL040$1] (t1_14);
[EL045$1] (t1_15);

! MODEL CONSTRAINT section
t1_15 > t1_14;  ! Threshold ordering constraint
```

### Valid Combinations
- ✅ Slope-only + Threshold ordering
- ✅ Slope-only + Multiple threshold orderings
- ❌ Complete equality + Any other constraint (redundant)
- ❌ Slope-only + Slope-only (duplicate)

---

## Codebook Workflow

### Step 1: Identify Items Needing Constraints

**Complete Equality:**
- Search for items with identical wording across studies
- Example: AA102 in NE25 vs AA102_22 in NE22

**Slope-Only Equality:**
- Group items by developmental domain
- Example: All "fine motor" items share discrimination

**Threshold Ordering:**
- Identify developmental sequences
- Example: "sits" < "stands" < "walks" < "runs"

**Simplex Constraints:**
- Find intermediate milestones between anchors
- Example: "walks with support" is between "stands" and "walks independently"

### Step 2: Update Codebook JSON

Navigate to item in `codebook/data/codebook.json`:

```json
{
  "items": {
    "AA104": {
      "id": 2,
      "lexicons": {...},
      "psychometric": {
        "param_constraints": "Constrain all to AA102"
      }
    }
  }
}
```

### Step 3: Validate Constraints

**Check for circular dependencies:**
```
AA104 constrained to AA102
AA102 constrained to AA104  [ERROR: Circular!]
```

**Check for contradictions:**
```
AA104 tau$1 > AA102$1
AA104 tau$1 < AA102$1  [ERROR: Contradiction!]
```

**Verify reference items exist:**
```
"Constrain all to AA999"  [ERROR: AA999 not in dataset!]
```

### Step 4: Generate Syntax

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/run_calibration_workflow.R
```

### Step 5: Review Excel Output

Open `mplus/generated_syntax.xlsx` and verify:
- **MODEL sheet:** Parameter labels match constraints
- **CONSTRAINT sheet:** Equality/inequality constraints correct
- **PRIOR sheet:** N(1,1) priors on discrimination parameters

---

## Common Patterns

### Pattern 1: Domain-Based Constraints

All items in "motor" domain share discrimination:

```json
{
  "GM010": {
    "psychometric": {
      "param_constraints": "Constrain slope to GM001"
    }
  },
  "GM020": {
    "psychometric": {
      "param_constraints": "Constrain slope to GM001"
    }
  }
}
```

### Pattern 2: Developmental Hierarchy

Enforce milestone ordering:

```json
{
  "GM010": {
    "content": {"stems": {"combined": "Sits without support"}}
  },
  "GM020": {
    "content": {"stems": {"combined": "Stands with support"}},
    "psychometric": {
      "param_constraints": "Constrain tau$1 to be greater than GM010$1"
    }
  },
  "GM030": {
    "content": {"stems": {"combined": "Walks independently"}},
    "psychometric": {
      "param_constraints": "Constrain tau$1 to be greater than GM020$1"
    }
  }
}
```

### Pattern 3: Cross-Study Equating

Link identical items across studies:

```json
{
  "AA102": {
    "lexicons": {
      "equate": "AA102",
      "ne25": "AA102",
      "ne22": "AA102_22",
      "ne20": "AA102_20"
    }
  },
  "AA102_22": {
    "psychometric": {
      "param_constraints": "Constrain all to AA102"
    }
  },
  "AA102_20": {
    "psychometric": {
      "param_constraints": "Constrain all to AA102"
    }
  }
}
```

---

## Troubleshooting

### Issue: "Missing param_constraints field"

**Cause:** Codebook not updated with renamed field

**Solution:** Ensure codebook uses `param_constraints` not `constraints`

### Issue: "Reference item not found"

**Cause:** Constraint references item not in calibration dataset

**Solution:**
1. Check reference item exists in `calibration_dataset_2020_2025` table
2. Verify item has non-missing `lex_equate` in codebook
3. Check item appears in at least one study

### Issue: "Circular constraint dependency"

**Cause:** Item A constrained to Item B, Item B constrained to Item A

**Solution:** Choose one item as "anchor" and constrain others to it

### Issue: "Contradictory constraints"

**Cause:** Multiple constraints conflict (e.g., tau$1 > X and tau$1 < X)

**Solution:** Review developmental theory, remove contradictory constraint

---

## References

- **Mplus Documentation:** [statmodel.com](https://www.statmodel.com/)
- **IRT Theory:** Embretson & Reise (2000). *Item Response Theory for Psychologists*
- **Graded Response Model:** Samejima (1969). *Estimation of latent ability using a response pattern of graded scores*

---

**Migrated:** January 2025
**Maintained By:** Kidsights Data Platform Team
