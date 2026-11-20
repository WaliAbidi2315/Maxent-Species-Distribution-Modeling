# Shorea robusta Species Distribution Modelling

<p align="center">
  <img src="https://img.shields.io/badge/R-276DC3?style=for-the-badge&logo=r&logoColor=white" alt="R">
  <img src="https://img.shields.io/badge/MaxEnt-Species%20Distribution%20Modelling-2E6B45?style=for-the-badge" alt="MaxEnt">
  <img src="https://img.shields.io/badge/terra-Spatial%20Raster%20Analysis-4C8C4A?style=for-the-badge" alt="terra">
  <img src="https://img.shields.io/badge/sf-Spatial%20Vector%20Data-4477AA?style=for-the-badge" alt="sf">
  <img src="https://img.shields.io/badge/ggplot2-Visualisation-E69F00?style=for-the-badge" alt="ggplot2">
</p>

A species-distribution modelling project for **Sal (*Shorea robusta*)**, using occurrence records and environmental predictors to map relative habitat suitability across a seven-state study area in India.

## Project overview

The workflow documents occurrence-data cleaning, spatial filtering, environmental raster preparation, predictor screening, MaxEnt input preparation, and interpretation of continuous and thresholded suitability outputs.

The accompanying analysis materials are intended to make the modelling decisions and outputs easier to inspect. Model suitability is not proof of species presence and should be interpreted in light of sampling bias, predictor resolution, background selection, and model settings.

## Study design and workflow

1. Read occurrence coordinates and remove exact duplicate locations.
2. Restrict records to the selected states: Uttar Pradesh, Bihar, Jharkhand, Odisha, Chhattisgarh, West Bengal, and Madhya Pradesh.
3. Prepare environmental predictors: 19 WorldClim bioclimatic variables, SRTM elevation, derived slope, and 2023 NDVI.
4. Align raster grids, crop and mask to the study area, and check missing cells.
5. Thin occurrence records to one record per approximately 1 km raster cell.
6. Sample background locations and inspect predictor correlations.
7. Export selected environmental layers and occurrence points for MaxEnt.
8. Produce continuous and binary suitability maps and supporting tables.

## Reported model output

The accompanying report describes a test AUC of **0.851**, with 1,794 training presence records and 598 test records. The binary suitability illustration uses the reported 10th-percentile training-presence threshold of **0.332**.

These figures are reported from the supplied project outputs; this repository does not independently reproduce the model unless the matching predictor rasters, occurrence inputs, MaxEnt configuration, and software dependencies are also available.

## Technology

- R
- MaxEnt
- terra and geodata for raster and geographic data
- sf for vector data
- dplyr for data manipulation
- ggplot2 for visualisation
- WorldClim, SRTM, and Sentinel-2-derived NDVI predictors

## Repository contents

- `analysis/` — R workflow supplied for the project
- `data/` — occurrence data (where included)
- `reports/` — HTML analysis and PDF report (where included)
- `figures/` and `tables/` — exported project outputs (where included)

## Reproducibility and data requirements

The supplied R script is a working-session analysis script rather than a fully automated, clean-session pipeline. It contains local file paths and later sections depend on objects created in earlier sections. Before rerunning it, update paths and ensure the required inputs are present, including the occurrence CSV, NDVI GeoTIFF, downloaded WorldClim and SRTM layers, study-area boundaries, and MaxEnt output raster.

The script references a local file named `Shorea_Robusta.csv`, `data/ndvi_mean_2023.tif`, and `maxent_out_cloglog_25/Shorea_robusta.asc`. Those inputs must be supplied separately if they are not present in the repository.

## Interpretation and limitations

- Presence-background modelling estimates relative suitability, not confirmed occupancy or abundance.
- Occurrence records may be spatially biased and do not necessarily represent a systematic survey.
- Raster alignment and resampling affect predictor values and should be considered when interpreting fine-scale patterns.
- The binary map depends on the selected threshold; it is one operational view of a continuous suitability surface.
- State-level suitable-area summaries are model-derived estimates, not ground-truthed habitat inventories.

## Citation and attribution

Environmental predictor sources and versions should be cited in any reuse of the analysis. The supplied script identifies WorldClim v2.1, SRTM elevation, and a 2023 Sentinel-2 SR Harmonized NDVI composite processed through Google Earth Engine.

---

**Project author:** Wali Abidi
