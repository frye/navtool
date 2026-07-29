#ifndef NAVTOOL_ROUTER_BRIDGE_H
#define NAVTOOL_ROUTER_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(NAVTOOL_ROUTER_BRIDGE_BUILDING)
#define NAVTOOL_ROUTER_BRIDGE_API __declspec(dllexport)
#else
#define NAVTOOL_ROUTER_BRIDGE_API __declspec(dllimport)
#endif
#elif defined(__GNUC__) || defined(__clang__)
#define NAVTOOL_ROUTER_BRIDGE_API __attribute__((visibility("default")))
#else
#define NAVTOOL_ROUTER_BRIDGE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define NAVTOOL_ROUTER_BRIDGE_ABI_VERSION 3u

enum {
    NAVTOOL_ROUTER_CAPABILITY_LAND_SEGMENT_CONSTRAINT_V1 = 1ull << 0
};

typedef int32_t navtool_router_status_v1;

enum {
    NAVTOOL_ROUTER_STATUS_OK_V1 = 0,
    NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1 = 1,
    NAVTOOL_ROUTER_STATUS_ALLOCATION_FAILURE_V1 = 2,
    NAVTOOL_ROUTER_STATUS_FILE_IO_V1 = 3,
    NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1 = 4,
    NAVTOOL_ROUTER_STATUS_UNSUPPORTED_FORECAST_V1 = 5,
    NAVTOOL_ROUTER_STATUS_INCOMPLETE_FORECAST_V1 = 6,
    NAVTOOL_ROUTER_STATUS_OUTSIDE_FORECAST_V1 = 7,
    NAVTOOL_ROUTER_STATUS_NO_ROUTE_V1 = 8,
    NAVTOOL_ROUTER_STATUS_OUTPUT_ERROR_V1 = 9,
    NAVTOOL_ROUTER_STATUS_INTERNAL_ERROR_V1 = 10,
    NAVTOOL_ROUTER_STATUS_FORECAST_EXHAUSTED_V2 = 11
};

typedef struct navtool_router_forecast_v1 navtool_router_forecast_v1;

typedef struct navtool_router_forecast_metadata_v1 {
    int64_t first_valid_utc_epoch_seconds;
    int64_t last_valid_utc_epoch_seconds;
    uint64_t latitude_count;
    uint64_t longitude_count;
    uint8_t global_longitude_coverage;
    uint8_t reserved[7];
} navtool_router_forecast_metadata_v1;

typedef struct navtool_router_wind_sample_v1 {
    double east_mps;
    double north_mps;
    uint8_t valid;
    uint8_t reserved[7];
} navtool_router_wind_sample_v1;

typedef struct navtool_router_coordinate_v1 {
    double latitude_degrees;
    double longitude_degrees;
} navtool_router_coordinate_v1;

typedef struct navtool_router_route_point_v1 {
    navtool_router_coordinate_v1 position;
    int64_t utc_epoch_seconds;
    double heading_degrees;
    double boat_speed_knots;
    double true_wind_speed_knots;
    double true_wind_direction_degrees;
    double cumulative_distance_nautical_miles;
} navtool_router_route_point_v1;

typedef struct navtool_router_diagnostics_v1 {
    uint64_t expanded_nodes;
    uint64_t generated_candidates;
    uint64_t retained_candidates;
    uint64_t time_steps;
} navtool_router_diagnostics_v1;

typedef struct navtool_router_progress_v1 {
    int64_t isochrone_utc_epoch_seconds;
    const navtool_router_coordinate_v1* isochrone_points;
    uint64_t isochrone_point_count;
    const navtool_router_route_point_v1* provisional_route_points;
    uint64_t provisional_route_point_count;
    navtool_router_diagnostics_v1 diagnostics;
} navtool_router_progress_v1;

/*
 * Progress views and their arrays are valid only for the duration of the
 * callback. The callback is synchronous and must return promptly.
 */
typedef void (*navtool_router_progress_callback_v1)(
    const navtool_router_progress_v1* progress,
    void* user_data);

typedef struct navtool_router_contour_segment_v2 {
    uint64_t point_offset;
    uint64_t point_count;
    uint8_t closed;
    uint8_t reserved[7];
} navtool_router_contour_segment_v2;

typedef struct navtool_router_progress_v2 {
    int64_t isochrone_utc_epoch_seconds;
    const navtool_router_coordinate_v1* contour_points;
    uint64_t contour_point_count;
    const navtool_router_contour_segment_v2* contour_segments;
    uint64_t contour_segment_count;
    const navtool_router_route_point_v1* provisional_route_points;
    uint64_t provisional_route_point_count;
    navtool_router_diagnostics_v1 diagnostics;
} navtool_router_progress_v2;

/*
 * Version 2 progress exposes router-lib display contour topology. All views
 * remain callback-scoped and must be copied before the callback returns.
 */
typedef void (*navtool_router_progress_callback_v2)(
    const navtool_router_progress_v2* progress,
    void* user_data);

typedef struct navtool_router_front_segment_v3 {
    uint64_t point_offset;
    uint64_t point_count;
} navtool_router_front_segment_v3;

typedef struct navtool_router_progress_v3 {
    int64_t isochrone_utc_epoch_seconds;
    const navtool_router_coordinate_v1* front_points;
    uint64_t front_point_count;
    const navtool_router_front_segment_v3* front_segments;
    uint64_t front_segment_count;
    const navtool_router_route_point_v1* provisional_route_points;
    uint64_t provisional_route_point_count;
    navtool_router_diagnostics_v1 diagnostics;
} navtool_router_progress_v3;

/*
 * Version 3 progress exposes one logical destination-facing isochrone front.
 * Segments are open and split only at map discontinuities such as the
 * antimeridian. All views remain callback-scoped.
 */
typedef void (*navtool_router_progress_callback_v3)(
    const navtool_router_progress_v3* progress,
    void* user_data);

NAVTOOL_ROUTER_BRIDGE_API uint32_t
navtool_router_bridge_abi_version_v1(void);

/*
 * Additive ABI-v1 feature bits. Older ABI-v1 bridges may not export this
 * function; consumers must treat a missing export as zero capabilities.
 */
NAVTOOL_ROUTER_BRIDGE_API uint64_t
navtool_router_bridge_capabilities_v1(void);

NAVTOOL_ROUTER_BRIDGE_API const char*
navtool_router_last_error_v1(void);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_forecast_load_v1(
    const char* grib_path_utf8,
    navtool_router_forecast_v1** out_forecast);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_forecast_load_bounded_v1(
    const char* grib_path_utf8,
    double south_latitude_degrees,
    double west_longitude_degrees,
    double north_latitude_degrees,
    double east_longitude_degrees,
    navtool_router_forecast_v1** out_forecast);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_forecast_destroy_v1(
    navtool_router_forecast_v1** forecast);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_forecast_get_metadata_v1(
    const navtool_router_forecast_v1* forecast,
    navtool_router_forecast_metadata_v1* out_metadata,
    char** out_source_utf8,
    size_t* out_source_length);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_v1(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    char** out_route_json_utf8,
    size_t* out_route_json_length);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_streaming_v1(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    navtool_router_progress_callback_v1 on_progress,
    void* progress_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_streaming_v2(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    navtool_router_progress_callback_v2 on_progress,
    void* progress_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length);

NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_streaming_v3(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    navtool_router_progress_callback_v3 on_progress,
    void* progress_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length);

/*
 * Samples are row-major from south to north, then west to east, including
 * both bounds. A one-point axis samples its midpoint. West > east crosses
 * the antimeridian. Individual interpolation failures set valid to zero.
 */
NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_sample_grid_v1(
    const navtool_router_forecast_v1* forecast,
    double south_latitude_degrees,
    double west_longitude_degrees,
    double north_latitude_degrees,
    double east_longitude_degrees,
    uint32_t latitude_count,
    uint32_t longitude_count,
    int64_t utc_epoch_seconds,
    navtool_router_wind_sample_v1* samples,
    size_t sample_count);

NAVTOOL_ROUTER_BRIDGE_API void
navtool_router_bridge_free_v1(void* bridge_owned_memory);

/*
 * Lightweight preflight check: returns NAVTOOL_ROUTER_BRIDGE_ABI_VERSION.
 * Calling this function verifies that the library is loaded and the versioned
 * v1 ABI symbol is present, without requiring a GRIB file.
 */
NAVTOOL_ROUTER_BRIDGE_API uint32_t
navtool_router_bridge_preflight_v1(void);

/* ---- GRIB inspection ---- */

enum {
    NAVTOOL_ROUTER_MODEL_UNKNOWN_V1 = 0,
    NAVTOOL_ROUTER_MODEL_NOAA_GFS_V1 = 1,
    NAVTOOL_ROUTER_MODEL_ECMWF_IFS_V1 = 2
};

/*
 * Metadata returned by navtool_router_inspect_grib_v1.
 *
 * model_id is one of NAVTOOL_ROUTER_MODEL_*_V1.
 * All epoch fields are seconds since the Unix epoch (UTC).
 * Longitude fields are in the canonical [-180, 180] range; east may be less
 * than west when the described area crosses the antimeridian.
 */
typedef struct navtool_router_grib_descriptor_v1 {
    int64_t  init_utc_epoch_seconds;
    int64_t  first_valid_utc_epoch_seconds;
    int64_t  last_valid_utc_epoch_seconds;
    double   south_latitude_degrees;
    double   west_longitude_degrees;
    double   north_latitude_degrees;
    double   east_longitude_degrees;
    int32_t  model_id;
    uint8_t  reserved[4];
} navtool_router_grib_descriptor_v1;

/*
 * Inspects a GRIB file using ecCodes without loading a full WeatherDataset.
 * Reads model identity, initialization time, valid-time range, and geographic
 * bounds from 10 m U/V wind messages. Validates that:
 *   - at least one U and one V message exist at 10 m height
 *   - all wind messages share a single model centre (not model-ambiguous)
 *   - all messages originate from a single model run (consistent init time)
 *   - the centre is a supported model (NCEP/GFS or ECMWF/IFS)
 *
 * Returns NAVTOOL_ROUTER_STATUS_OK_V1 and populates *out_descriptor on success.
 * Returns an appropriate error status and sets the thread-local error on failure.
 * The file is not copied; this call is read-only and does not retain any handle.
 */
NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_inspect_grib_v1(
    const char* grib_path_utf8,
    navtool_router_grib_descriptor_v1* out_descriptor);

#ifdef __cplusplus
}
#endif

#endif
