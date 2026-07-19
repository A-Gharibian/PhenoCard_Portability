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

**Selected lab features (Step 2)** → RDW, MCHC, Urea Nitrogen and White Blood Cells, identified as informative during Step 1 exploratory analysis. `p1_exploratory_first_admission_measurements.sql` is the standalone query used to inspect measurement density and distributions around the index admission; it is not part of either pipeline.

---

## Requirements

- [DuckDB](https://duckdb.org/) (tested via [DBeaver](https://dbeaver.io/))
- ATHENA vocabulary files ([athena.ohdsi.org](https://athena.ohdsi.org))
- MIMIC-IV access via [PhysioNet](https://physionet.org/content/mimiciv/)

> MIMIC-IV access requires PhysioNet credentialing.
> **This repository contains no patient data.**

---

## Quickstart

### Step 1
1. Download the ATHENA vocabulary bundle and **extract the .zip** into a single flat folder → `vocabulary/`.
   DuckDB cannot read inside a .zip archive, so this must be extracted first:
   - PowerShell: `Expand-Archive -Path vocabulary_download.zip -DestinationPath vocabulary\`
   - bash: `unzip vocabulary_download.zip -d vocabulary/`
2. Connect to your DB instance.
3. Run `00_create_vocabulary_tables.sql` — creates the empty OMOP vocabulary tables.
   *Skip this if your database is already an OMOP CDM instance where these tables exist.*
4. Set `vocab_path` in `00_load_vocabulary.sql` to your extracted folder, then run it.
5. Run `p1_build_pipeline.sql`.
6. (Optional) Run `p1_05_cohort_characterization.sql` for a cohort summary.

### Step 2
1. Place MIMIC-IV CSV files → `mimic/`
2. Set `mimic_path` in `p2_build_pipeline.sql`, then run it.
3. (Optional) Run `p2_05_apply_demographic_filters.sql` to apply age/gender filters.
4. (Optional) Run `p2_06_cohort_characterization.sql` for a cohort summary.

> Steps 2–4 of the Step 2 sequence share a session variable (`mimic_path`). Run them in the
> same DBeaver session, or uncomment the `SET variable mimic_path` line at the top of `p2_05`.

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

- `valid_start_date` / `valid_end_date` in `concept`, `concept_relationship`, and `drug_strength` are parsed as `DATE`. The ATHENA `YYYYMMDD` format is handled explicitly via `dateformat = '%Y%m%d'` in `00_load_vocabulary.sql`. These columns are not used in any pipeline query. *(Databases loaded with an earlier revision of the loader may hold these as `BIGINT`; this is harmless for the same reason.)*
- `anchor_age` in MIMIC-IV is the patient's age at their de-identified anchor year — used as a proxy for age at the index date in Step 2.
- Patients with no lab results in the 6-month lookback window will have `NULL` feature values in `p2_final_ml_matrix`. Handle missing data before model training.

---

## Known Limitations

- **Asymmetric index date definition (Step 1).** Cases are indexed at their first diagnosis date; controls at their most recent visit date. Controls are therefore observed over a longer history by construction, introducing a potential observation-window imbalance. A more rigorous design would use risk-set sampling to draw control index dates. This is not implemented here to keep the pipeline simple and transparent for a demonstrative project.
- **Propensity score matching is not implemented for MIMIC-IV.** The 10,000-patient Step 2 pool is drawn at random and is not demographically matched to the Step 1 cohort. The two `*_cohort_characterization.sql` scripts are provided to quantify how far apart the cohorts are, but no matching step is applied. **Any direct comparison of Step 1 and Step 2 results is therefore confounded by cohort composition** and should be read as indicative only.
- **Age is not directly available** in either OMOP or MIMIC-IV due to de-identification. `year_of_birth` (Step 1) and `anchor_age` (Step 2) are proxies, not true ages.

---

## Citation

If you use this pipeline or the associated dataset, please cite:
[under review]
---

## License

Code in this repository is released under the **MIT License** — see [LICENSE](LICENSE) for the full text.

MIMIC-IV data is subject to the [PhysioNet Credentialed Health Data License](https://physionet.org/content/mimiciv/view-license/3.1/).
ATHENA vocabulary files are subject to the [OHDSI vocabulary license](https://athena.ohdsi.org).
