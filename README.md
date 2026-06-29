# PhenoCard_Portability

A two-step SQL pipeline validating phenotype-derived features across cohort sizes and vocabularies, using OMOP-mapped and raw MIMIC-IV data.

| | Step 1 | Step 2 |
| :--- | :--- | :--- |
| **Sample size** | 100 patients | 10,000 patients |
| **Vocabulary** | OMOP/ATHENA | Raw ICD codes |
| **Clinical label** | `concept_ancestor` (concept_id 4068155) | ICD-9/10 text match |
| **Features** | All conditions + all measurements | 4 pre-selected lab values |
| **Lookback window** | All history to index date | 6 months before index date |
| **Demographics** | `year_of_birth`, `gender` from OMOP | Optional via `p2_05` |

**Selected lab features (Step 2)** → identified as informative during Step 1 exploratory analysis.

---

## Requirements

- [DuckDB](https://duckdb.org/) (tested via [DBeaver](https://dbeaver.io/))
- ATHENA vocabulary files ([athena.ohdsi.org](https://athena.ohdsi.org))
- MIMIC-IV access via [PhysioNet](https://physionet.org/content/mimiciv/)

> MIMIC-IV access requires PhysioNet credentialing and the CITI data privacy course. **This repository contains no patient data.**

---

## Quickstart

### Step 1
1. Download ATHENA vocabulary files → `vocabulary/`
2. Connect to your DB instance.
3. Run `00_load_vocabulary.sql`.
4. Run `phase1_build_pipeline.sql`.
5. (Optional) Run `p1_05_cohort_characterization.sql` for a cohort summary.

### Step 2
1. Place MIMIC-IV CSV files → `mimic/`
2. Run `phase2_build_pipeline.sql`.
3. (Optional) Run `p2_05_apply_demographic_filters.sql` to apply age/gender filters.

---

## Naming Conventions

| Convention | Detail |
| :--- | :--- |
| `person_id` | OMOP CDM standard patient identifier (Step 1 clinical tables) |
| `subject_id` | OHDSI cohort convention for derived/analytical tables |
| `p2_` prefix | All Step 2 tables and files, to avoid clashing with Step 1 |
| `target_ecg_afib` | Binary outcome label (consistent across both steps) |
| `index_date` | Anchor date for all feature extraction — no features after this date |

---

## Data Notes

- `valid_start_date` / `valid_end_date` in `concept`, `concept_relationship`, and `drug_strength` are stored as `BIGINT` due to a DuckDB CSV parsing artifact with the ATHENA date format. These are not used in any pipeline query.
- `anchor_age` in MIMIC-IV is the patient's age at their de-identified anchor year — used as a proxy for age at the index date in Step 2.
- Patients with no lab results in the 6-month lookback window will have `NULL` feature values in `p2_final_ml_matrix`. Handle missing data before model training.

---

## Known Limitations

- **Asymmetric index date definition (Step 1).** Cases are indexed at their first diagnosis date; controls at their most recent visit date. Controls are therefore observed over a longer history by construction, introducing a potential observation-window imbalance. A more rigorous design would use risk-set sampling to draw control index dates. This is not implemented here to keep the pipeline simple and transparent for a demonstrative project.
- **Step 2 random sampling is not demographically matched to Step 1.** The 10,000-patient MIMIC-IV pool is drawn at random; comparisons to the Step 1 cohort require explicit propensity score matching (performed in R) before the two cohorts can be considered comparable.
- **Age is not directly available** in either OMOP or MIMIC-IV due to de-identification. `year_of_birth` (Step 1) and `anchor_age` (Step 2) are proxies, not true ages, and are anchored to different de-identification schemes.

---

## Citation

If you use this pipeline or the associated dataset, please cite:
[under review]
---

## License

Code in this repository is released under the **MIT License** — see [LICENSE](LICENSE) for the full text.

MIMIC-IV data is subject to the [PhysioNet Credentialed Health Data License](https://physionet.org/content/mimiciv/view-license/3.1/).
ATHENA vocabulary files are subject to the [OHDSI vocabulary license](https://athena.ohdsi.org).
