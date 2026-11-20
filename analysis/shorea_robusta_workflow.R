# Shorea robusta species distribution modelling workflow
# Supplied project code, consolidated into a single reference script.
#
# Before running:
# 1. Set the working directory to the project root.
# 2. Place Shorea_Robusta.csv in the project root.
# 3. Place data/ndvi_mean_2023.tif in data/.
# 4. Ensure the MaxEnt output exists at
#    maxent_out_cloglog_25/Shorea_robusta.asc before running map-export sections.
# 5. This script is stateful: later sections use objects created earlier.
#    Run sequentially in a fresh R session after checking all inputs.
#
# Packages used across the supplied workflow:
# dplyr, ggplot2, geodata, sf, terra

library(dplyr)
library(ggplot2)
library(geodata)
library(sf)
library(terra)

# Project paths ---------------------------------------------------------
# Replace this path with your own project folder.
# setwd("C:/path/to/Maxent-Species-Distribution-Modeling")
dir.create("data", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)
dir.create("processed", showWarnings = FALSE)
dir.create("maxent_in", showWarnings = FALSE)
dir.create("maxent_occ", showWarnings = FALSE)
dir.create("tables", showWarnings = FALSE)

# 1. Occurrence data cleaning ------------------------------------------
raw <- read.csv("Shorea_Robusta.csv")
pts <- data.frame(species = "Shorea robusta", lon = raw$LON, lat = raw$LAT)
cat("Starting records:", nrow(pts), "\n")

pts <- distinct(pts, lon, lat, .keep_all = TRUE)
cat("After removing exact duplicates:", nrow(pts), "\n")

# 2. Define study area and spatially filter points ----------------------
study_states <- c(
  "Uttar Pradesh", "Bihar", "Jharkhand", "Odisha",
  "Chhattisgarh", "West Bengal", "Madhya Pradesh"
)
states <- geodata::gadm("IND", level = 1, path = ".")
study_area <- states[states$NAME_1 %in% study_states, ]
print(study_area$NAME_1)

pts_v <- terra::vect(pts, geom = c("lon", "lat"), crs = "EPSG:4326")
inside <- terra::relate(pts_v, study_area, "within") |> rowSums() > 0
pts <- pts[inside, ]
cat("Records inside study area:", nrow(pts), "\n")

# Map occurrence locations across India
india <- sf::st_as_sf(geodata::gadm("IND", level = 0, path = "."))
ggplot() +
  geom_sf(data = india, fill = "grey95") +
  geom_point(data = pts, aes(lon, lat), size = 0.6, colour = "darkgreen") +
  theme_minimal()

# 3. Download and prepare environmental predictors ---------------------
bio <- geodata::worldclim_country("IND", var = "bio", res = 0.5, path = "data")
dem <- geodata::elevation_30s(country = "IND", path = "data")
ndvi <- terra::rast("data/ndvi_mean_2023.tif")
names(bio) <- paste0("bio", 1:19)

e <- terra::ext(study_area)
box <- terra::ext(
  terra::xmin(e) - 0.1, terra::xmax(e) + 0.1,
  terra::ymin(e) - 0.1, terra::ymax(e) + 0.1
)
bio_c <- terra::crop(bio, box)
dem_c <- terra::crop(dem, box)
ndvi_c <- terra::crop(ndvi, box)

dem_c <- terra::resample(dem_c, bio_c, method = "bilinear")
names(dem_c) <- "elev"
ndvi_c <- terra::resample(ndvi_c, bio_c, method = "bilinear")
names(ndvi_c) <- "ndvi"

slope <- terra::terrain(dem_c, v = "slope", unit = "degrees")
names(slope) <- "slope"

env <- c(bio_c, dem_c, slope, ndvi_c)
env <- terra::mask(env, study_area)
env <- terra::mask(env, terra::any(is.na(env)), maskvalues = TRUE)

# Checks: grid geometry and predictor ranges
print(terra::compareGeom(bio_c, dem_c, slope, ndvi_c))
print(env)
print(terra::global(env[["ndvi"]], range, na.rm = TRUE))
print(terra::global(env[["elev"]], range, na.rm = TRUE))

plot(env[[c("bio1", "bio12", "elev", "slope", "ndvi")]])
terra::writeRaster(
  env, "processed/env_all_aligned.tif", overwrite = TRUE
)

# 4. Thin occurrences to one point per raster cell ---------------------
xy <- cbind(pts$lon, pts$lat)
cells <- terra::cellFromXY(env[[1]], xy)
has_data <- !is.na(terra::extract(env[[1]], xy)[, 1])
keep <- has_data & !is.na(cells) & !duplicated(cells)
pts_thin <- pts[keep, ]
cat("Before thinning:", nrow(pts), "After thinning:", nrow(pts_thin), "\n")

# 5. Background sample and predictor correlation -----------------------
set.seed(42)
bg <- terra::spatSample(
  env, 10000, method = "random", na.rm = TRUE, as.df = TRUE
)
cm <- cor(bg, use = "complete.obs")
write.csv(round(cm, 2), "figures/correlation_matrix.csv")

hi <- which(abs(cm) > 0.7 & upper.tri(cm), arr.ind = TRUE)
pairs_hi <- data.frame(
  var1 = rownames(cm)[hi[, 1]],
  var2 = colnames(cm)[hi[, 2]],
  r = round(cm[hi], 2)
)
pairs_hi <- pairs_hi[order(-abs(pairs_hi$r)), ]
print(pairs_hi, row.names = FALSE)

chosen <- c("bio1", "bio4", "bio12", "bio15", "bio17",
            "elev", "slope", "ndvi")
candidates <- setdiff(colnames(cm), chosen)
correlation_screen <- data.frame(
  variable = candidates,
  max_abs_r = sapply(candidates, function(v) max(abs(cm[v, chosen]))),
  most_correlated_with = sapply(
    candidates, function(v) chosen[which.max(abs(cm[v, chosen]))]
  )
)
correlation_screen <- correlation_screen[order(correlation_screen$max_abs_r), ]
print(correlation_screen, row.names = FALSE)

# 6. Export selected MaxEnt inputs --------------------------------------
final_vars <- c(
  "bio1", "bio4", "bio10", "bio12", "bio15",
  "bio17", "elev", "slope", "ndvi"
)
env_final <- env[[final_vars]]

unlink("maxent_in", recursive = TRUE)
dir.create("maxent_in", showWarnings = FALSE)
for (v in final_vars) {
  terra::writeRaster(
    env_final[[v]], file.path("maxent_in", paste0(v, ".asc")),
    filetype = "AAIGrid", NAflag = -9999, overwrite = TRUE
  )
}

write.csv(
  pts_thin[, c("species", "lon", "lat")],
  "maxent_occ/occurrences.csv", row.names = FALSE
)
cat("Selected predictor grids:", length(final_vars), "\n")
cat("Thinned occurrence records:", nrow(pts_thin), "\n")

# Optional export of all 22 predictor layers
unlink("maxent_in_all", recursive = TRUE)
dir.create("maxent_in_all", showWarnings = FALSE)
for (v in names(env)) {
  terra::writeRaster(
    env[[v]], file.path("maxent_in_all", paste0(v, ".asc")),
    filetype = "AAIGrid", NAflag = -9999, overwrite = TRUE
  )
}

# 7. Terrain diagnostics ------------------------------------------------
bg_slope <- bg$slope
print(summary(bg_slope))
print(quantile(bg_slope, c(.1, .25, .5, .75, .9)))
print(mean(bg_slope < 1))

sl <- env[["slope"]]
print(terra::global(sl == 0, "mean", na.rm = TRUE))
vals <- terra::extract(sl, cbind(pts_thin$lon, pts_thin$lat))[, 1]
print(mean(vals == 0, na.rm = TRUE))
print(summary(vals))

# 8. Suitability maps and state summaries -------------------------------
# Requires the MaxEnt cloglog raster generated outside this R script.
suit_path <- "maxent_out_cloglog_25/Shorea_robusta.asc"
if (file.exists(suit_path)) {
  suit <- terra::rast(suit_path)
  terra::crs(suit) <- "EPSG:4326"
  suit <- terra::mask(suit, study_area)

  png("figures/fig_suitability_map.png",
      width = 2400, height = 2000, res = 300)
  plot(
    suit, col = hcl.colors(100, "YlOrRd", rev = TRUE), range = c(0, 1),
    xlab = "Longitude (°E)", ylab = "Latitude (°N)",
    main = "Habitat suitability for Shorea robusta (cloglog output)",
    plg = list(title = "Suitability")
  )
  plot(study_area, add = TRUE, border = "grey30", lwd = 0.8)
  terra::sbar(500, xy = "bottomright", type = "bar", divs = 2, below = "km")
  terra::north(xy = "topleft", type = 1)
  dev.off()

  threshold <- 0.332
  binary <- suit >= threshold
  png("figures/fig_suitability_binary.png",
      width = 2400, height = 2000, res = 300)
  plot(
    binary, col = c("grey90", "darkgreen"), legend = FALSE,
    xlab = "Longitude (°E)", ylab = "Latitude (°N)",
    main = paste0("Predicted suitable habitat (cloglog >= ", threshold, ")")
  )
  plot(study_area, add = TRUE, border = "grey30", lwd = 0.8)
  legend(
    "bottomleft", inset = 0.03, legend = c("Unsuitable", "Suitable"),
    fill = c("grey90", "darkgreen"), bty = "n"
  )
  terra::sbar(500, xy = "bottomright", type = "bar", divs = 2, below = "km")
  terra::north(xy = "topleft", type = 1)
  dev.off()

  areas <- terra::cellSize(binary, unit = "km")
  by_state <- terra::extract(
    areas * binary, study_area, fun = sum, na.rm = TRUE
  )
  total <- terra::extract(areas, study_area, fun = sum, na.rm = TRUE)
  state_suitability <- data.frame(
    state = study_area$NAME_1,
    suitable_km2 = round(by_state[, 2]),
    pct_suitable = round(100 * by_state[, 2] / total[, 2], 1)
  )
  print(state_suitability)
} else {
  message(
    "Skipping suitability map export: MaxEnt output raster not found at ",
    suit_path
  )
}

# 9. Export report tables and diagnostic figures -----------------------
raw <- read.csv("Shorea_Robusta.csv")
clean_tbl <- data.frame(
  Step = c(
    "Raw occurrence records",
    "After removing exact duplicate coordinates",
    "Inside the seven study states",
    "After thinning to one record per ~1 km cell"
  ),
  Records = c(
    nrow(raw),
    nrow(distinct(raw, LON, LAT)),
    nrow(pts),
    nrow(pts_thin)
  )
)
write.csv(clean_tbl, "tables/table_cleaning_steps.csv", row.names = FALSE)

bio_desc <- c(
  "Annual mean temperature",
  "Mean diurnal range (mean monthly maximum minus minimum temperature)",
  "Isothermality (bio2 / bio7 x 100)",
  "Temperature seasonality (standard deviation x 100)",
  "Maximum temperature of warmest month",
  "Minimum temperature of coldest month",
  "Temperature annual range (bio5 - bio6)",
  "Mean temperature of wettest quarter",
  "Mean temperature of driest quarter",
  "Mean temperature of warmest quarter",
  "Mean temperature of coldest quarter",
  "Annual precipitation",
  "Precipitation of wettest month",
  "Precipitation of driest month",
  "Precipitation seasonality (coefficient of variation)",
  "Precipitation of wettest quarter",
  "Precipitation of driest quarter",
  "Precipitation of warmest quarter",
  "Precipitation of coldest quarter"
)
bio_unit <- c(
  "°C", "°C", "%", "°C x 100", "°C", "°C", "°C", "°C", "°C",
  "°C", "°C", "mm", "mm", "mm", "%", "mm", "mm", "mm", "mm"
)
var_tbl <- data.frame(
  Variable = c(paste0("bio", 1:19), "elev", "slope", "ndvi"),
  Description = c(
    bio_desc, "Elevation above sea level",
    "Terrain slope derived from elevation",
    "Mean NDVI composite, 2023 (cloud-masked Sentinel-2)"
  ),
  Unit = c(bio_unit, "m", "degrees", "unitless (-1 to 1)"),
  Source = c(
    rep("WorldClim v2.1 (Fick & Hijmans, 2017)", 19),
    "SRTM (Farr et al., 2007)", "Derived from SRTM",
    "Sentinel-2 SR Harmonized via Google Earth Engine"
  ),
  Resolution = "30 arc-seconds (~1 km) after resampling",
  Processing = c(
    rep("Clipped to study area", 19),
    "Clipped; bilinear resampling to WorldClim grid",
    "Calculated with terra::terrain on WorldClim grid",
    "Exported from GEE; clipped; bilinear resampling"
  )
)
write.csv(var_tbl, "tables/table_environmental_variables.csv", row.names = FALSE)

png("figures/fig_correlation_heatmap.png",
    width = 2400, height = 2200, res = 250)
par(mar = c(6, 6, 3, 1))
image(
  1:ncol(cm), 1:nrow(cm), abs(cm)[, nrow(cm):1],
  axes = FALSE, xlab = "", ylab = "",
  col = hcl.colors(20, "YlOrRd", rev = TRUE), zlim = c(0, 1),
  main = "Absolute pairwise correlation between predictors"
)
axis(1, 1:ncol(cm), colnames(cm), las = 2, cex.axis = 0.7)
axis(2, 1:nrow(cm), rev(rownames(cm)), las = 2, cex.axis = 0.7)
dev.off()

cat("\nWorkflow finished. Review figures/ and tables/ outputs.\n")
