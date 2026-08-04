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

#define NAVTOOL_ROUTER_BRIDGE_ABI_VERSION 7u

enum {
    NAVTOOL_ROUTER_CAPABILITY_LAND_SEGMENT_CONSTRAINT_V1 = 1ull << 0,
    /* Stage 3 environment payload and navtool_router_calculate_route_streaming_v7. */
    NAVTOOL_ROUTER_CAPABILITY_ENVIRONMENT_V7 = 1ull << 1,
    NAVTOOL_ROUTER_CAPABILITY_CURRENT_PROVIDER_V7 = 1ull << 2,
    NAVTOOL_ROUTER_CAPABILITY_SEA_STATE_V7 = 1ull << 3,
    NAVTOOL_ROUTER_CAPABILITY_SIGNED_DISTANCE_LAND_V7 = 1ull << 4,
    NAVTOOL_ROUTER_CAPABILITY_EXCLUSION_ZONES_V7 = 1ull << 5
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
    NAVTOOL_ROUTER_STATUS_FORECAST_EXHAUSTED_V2 = 11,
    /*
     * The environment payload is internally contradictory, for example a wave
     * field with no sea-state model or a clearance with no landmask. Reported
     * before any search begins.
     */
    NAVTOOL_ROUTER_STATUS_INVALID_ENVIRONMENT_V7 = 12,
    /*
     * A configured provider had no usable sample and its missing-data policy
     * fails the route. Never reinterpreted as zero current, calm sea, or open
     * water.
     */
    NAVTOOL_ROUTER_STATUS_ENVIRONMENT_DATA_UNAVAILABLE_V7 = 13
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

/*
 * Segment views are valid only for the synchronous callback. Returning nonzero
 * accepts the candidate segment; returning zero rejects it before retention.
 */
typedef uint8_t (*navtool_router_segment_eligibility_callback_v1)(
    const navtool_router_coordinate_v1* parent,
    const navtool_router_coordinate_v1* candidate,
    void* user_data);

typedef struct navtool_router_progress_v5 {
    int64_t isochrone_utc_epoch_seconds;
    const navtool_router_coordinate_v1* contour_points;
    uint64_t contour_point_count;
    const navtool_router_contour_segment_v2* contour_segments;
    uint64_t contour_segment_count;
    const navtool_router_coordinate_v1* front_points;
    uint64_t front_point_count;
    const navtool_router_front_segment_v3* front_segments;
    uint64_t front_segment_count;
    const navtool_router_route_point_v1* provisional_route_points;
    uint64_t provisional_route_point_count;
    navtool_router_diagnostics_v1 diagnostics;
} navtool_router_progress_v5;

/*
 * Version 5 progress exposes the full retained reachability contour topology
 * together with the current destination-facing front. All views remain
 * callback-scoped and must be copied before the callback returns.
 */
typedef void (*navtool_router_progress_callback_v5)(
    const navtool_router_progress_v5* progress,
    void* user_data);

enum {
    NAVTOOL_ROUTER_SOLVER_ISOCHRONE_BEAM_V6 = 0,
    NAVTOOL_ROUTER_SOLVER_TIME_DEPENDENT_LATTICE_V6 = 1
};

typedef struct navtool_router_options_v6 {
    int32_t solver;
    int32_t heading_augmentation;
    int32_t wind_sampling;
    int32_t polar_angle_interpolation;
    int32_t above_polar_range;
    int32_t pruning_strategy;
    int32_t destination_front_segment_policy;
    int32_t lattice_search_algorithm;
    int64_t tack_penalty_seconds;
    int64_t gybe_penalty_seconds;
    int64_t midpoint_wind_sampling_threshold_minutes;
    int64_t lattice_time_bucket_minutes;
    double downwind_true_wind_angle_degrees;
    double maximum_true_wind_speed_knots;
    double pruning_sector_degrees;
    double destination_front_half_angle_degrees;
    double lattice_corridor_width_nautical_miles;
    uint64_t destination_front_minimum_secondary_segment_points;
    uint64_t lattice_subdivision_level;
    uint64_t lattice_refinement_levels;
    uint64_t lattice_corridor_widening_retries;
    uint64_t lattice_progress_every_n_expansions;
    uint64_t flags;
} navtool_router_options_v6;

enum {
    NAVTOOL_ROUTER_OPTIONS_HAS_MAXIMUM_TRUE_WIND_SPEED_V6 = 1ull << 0
};

typedef struct navtool_router_lattice_search_progress_v6 {
    uint64_t settled_labels;
    uint64_t queued_labels;
    uint64_t relaxed_labels;
    uint64_t refinement_index;
    uint64_t subdivision_level;
} navtool_router_lattice_search_progress_v6;

typedef struct navtool_router_progress_v6 {
    int32_t solver;
    int32_t reserved;
    int64_t progress_utc_epoch_seconds;
    const navtool_router_coordinate_v1* contour_points;
    uint64_t contour_point_count;
    const navtool_router_contour_segment_v2* contour_segments;
    uint64_t contour_segment_count;
    const navtool_router_coordinate_v1* front_points;
    uint64_t front_point_count;
    const navtool_router_front_segment_v3* front_segments;
    uint64_t front_segment_count;
    const navtool_router_coordinate_v1* search_points;
    uint64_t search_point_count;
    const navtool_router_route_point_v1* provisional_route_points;
    uint64_t provisional_route_point_count;
    navtool_router_diagnostics_v1 diagnostics;
    navtool_router_lattice_search_progress_v6 lattice_search;
} navtool_router_progress_v6;

/*
 * Return nonzero to continue routing or zero to cancel. All views remain
 * callback-scoped.
 */
typedef uint8_t (*navtool_router_progress_callback_v6)(
    const navtool_router_progress_v6* progress,
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
 * Adds pre-retention segment eligibility to the v3 destination-front stream.
 * The eligibility callback is required when this entry point is used.
 */
NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_streaming_v4(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    navtool_router_progress_callback_v3 on_progress,
    void* progress_user_data,
    navtool_router_segment_eligibility_callback_v1 is_segment_eligible,
    void* segment_eligibility_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length);

/*
 * Combines full display contours and destination-front progress with optional
 * pre-retention segment eligibility.
 */
NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_streaming_v5(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    navtool_router_progress_callback_v5 on_progress,
    void* progress_user_data,
    navtool_router_segment_eligibility_callback_v1 is_segment_eligible,
    void* segment_eligibility_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length);

/*
 * Configuration-driven router-lib v0.4 entry point. Beam progress includes
 * contours/fronts; lattice progress includes search points instead. Views are
 * synchronous and callback-scoped.
 */
NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_streaming_v6(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    const navtool_router_options_v6* options,
    navtool_router_progress_callback_v6 on_progress,
    void* progress_user_data,
    navtool_router_segment_eligibility_callback_v1 is_segment_eligible,
    void* segment_eligibility_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length);

/* ---- Stage 3 environment payload (ABI v7) ---- */

/*
 * The environment payload is plain data, never a callback, so router-lib's
 * worker threads never re-enter the caller while sampling. Every pointer below
 * is borrowed for the duration of the calculate call only; the bridge copies
 * whatever it needs into immutable router-lib providers before searching.
 *
 * Units and reference frames match router-lib exactly:
 *   - Positions are canonical degrees, longitude in [-180, 180].
 *   - Times are UTC whole seconds.
 *   - Current is an east/north vector in knots pointing the way the water
 *     flows (oceanographic set), the opposite of the meteorological wind
 *     convention.
 *   - Significant wave height is metres, period is seconds, and wave direction
 *     is the meteorological direction waves come *from*, degrees true.
 *   - Signed land distance is nautical miles, positive over water and negative
 *     over land.
 *
 * Every string is NUL-terminated UTF-8 and may be null, which is read as empty.
 */

enum {
    NAVTOOL_ROUTER_MISSING_DATA_FAIL_ROUTE_V7 = 0,
    NAVTOOL_ROUTER_MISSING_DATA_REJECT_TRANSITION_V7 = 1
};

enum {
    NAVTOOL_ROUTER_EXCLUSION_BOUNDARY_EXCLUDED_V7 = 0,
    NAVTOOL_ROUTER_EXCLUSION_BOUNDARY_ALLOWED_V7 = 1
};

enum {
    NAVTOOL_ROUTER_ENVIRONMENT_SAMPLING_SEGMENT_START_V7 = 0,
    NAVTOOL_ROUTER_ENVIRONMENT_SAMPLING_MIDPOINT_V7 = 1
};

enum {
    NAVTOOL_ROUTER_FIELD_MODE_NONE_V7 = 0,
    NAVTOOL_ROUTER_FIELD_MODE_UNIFORM_V7 = 1,
    NAVTOOL_ROUTER_FIELD_MODE_GRID_V7 = 2
};

typedef struct navtool_router_provider_metadata_v7 {
    const char* name_utf8;
    const char* source_utf8;
    const char* revision_utf8;
} navtool_router_provider_metadata_v7;

/*
 * Regular latitude/longitude sample grid. Values are row-major from the
 * south-west corner at index row * longitude_count + column, with row
 * increasing north and column increasing east.
 */
typedef struct navtool_router_grid_spec_v7 {
    double south_latitude_degrees;
    double west_longitude_degrees;
    double latitude_step_degrees;
    double longitude_step_degrees;
    uint64_t latitude_count;
    uint64_t longitude_count;
    uint8_t global_longitude_coverage;
    uint8_t reserved[7];
} navtool_router_grid_spec_v7;

/*
 * mode selects which members are read. Uniform mode uses the two knots values;
 * grid mode uses grid plus both arrays, each holding
 * latitude_count * longitude_count finite values.
 */
typedef struct navtool_router_current_settings_v7 {
    int32_t mode;
    int32_t missing_data_policy;
    double uniform_east_knots;
    double uniform_north_knots;
    navtool_router_grid_spec_v7 grid;
    const double* east_knots;
    const double* north_knots;
    navtool_router_provider_metadata_v7 metadata;
} navtool_router_current_settings_v7;

/*
 * Coefficients of router-lib's built-in significant-wave-height derating
 * model. The retained speed fraction is
 *
 *   1 - min(maximum_loss_fraction,
 *           height_coefficient * Hs^height_exponent * directional_factor)
 *
 * where the directional factor interpolates between following_sea_factor,
 * one at a beam sea, and head_sea_factor.
 */
typedef struct navtool_router_wave_derating_v7 {
    double height_coefficient;
    double height_exponent;
    double head_sea_factor;
    double following_sea_factor;
    double maximum_loss_fraction;
    double period_sensitivity;
    double reference_period_seconds;
    double minimum_period_seconds;
} navtool_router_wave_derating_v7;

typedef struct navtool_router_wave_settings_v7 {
    int32_t mode;
    int32_t missing_data_policy;
    double uniform_significant_height_metres;
    double uniform_peak_period_seconds;
    double uniform_direction_from_degrees;
    navtool_router_grid_spec_v7 grid;
    const double* significant_height_metres;
    const double* peak_period_seconds;
    const double* direction_from_degrees;
    navtool_router_wave_derating_v7 derating;
    navtool_router_provider_metadata_v7 provider_metadata;
    navtool_router_provider_metadata_v7 model_metadata;
} navtool_router_wave_settings_v7;

/*
 * signed_distance_nautical_miles holds latitude_count * longitude_count finite
 * values. interpolation_error_nautical_miles is added to the clearance before
 * any segment is certified, so a mask that under-reports its own error can
 * never round a decision toward accepting land.
 */
typedef struct navtool_router_landmask_settings_v7 {
    uint8_t configured;
    uint8_t reserved[3];
    int32_t missing_data_policy;
    navtool_router_grid_spec_v7 grid;
    const double* signed_distance_nautical_miles;
    double resolution_nautical_miles;
    double interpolation_error_nautical_miles;
    double clearance_nautical_miles;
    uint64_t maximum_subdivision_depth;
    navtool_router_provider_metadata_v7 metadata;
} navtool_router_landmask_settings_v7;

/*
 * One closed ring, referencing a contiguous range of the flattened vertex
 * array. The ring is implicitly closed and edges are great-circle arcs, so a
 * ring may cross the antimeridian without special encoding.
 */
typedef struct navtool_router_exclusion_ring_v7 {
    uint64_t vertex_offset;
    uint64_t vertex_count;
} navtool_router_exclusion_ring_v7;

/* One simple polygon: an outer ring plus a contiguous range of hole rings. */
typedef struct navtool_router_exclusion_polygon_v7 {
    navtool_router_exclusion_ring_v7 outer;
    uint64_t hole_offset;
    uint64_t hole_count;
} navtool_router_exclusion_polygon_v7;

/*
 * A versioned, optionally time-limited zone. active_from/active_until bound a
 * half-open UTC interval; the has_* flags select whether each bound applies.
 * Identifier must be unique within the set and determines canonical ordering,
 * so input order can never change routing or diagnostics.
 */
typedef struct navtool_router_exclusion_zone_v7 {
    const char* identifier_utf8;
    const char* source_utf8;
    uint64_t revision;
    int64_t active_from_utc_epoch_seconds;
    int64_t active_until_utc_epoch_seconds;
    uint8_t has_active_from;
    uint8_t has_active_until;
    uint8_t reserved[6];
    uint64_t polygon_offset;
    uint64_t polygon_count;
} navtool_router_exclusion_zone_v7;

typedef struct navtool_router_exclusion_settings_v7 {
    uint8_t configured;
    uint8_t reserved[3];
    int32_t boundary_policy;
    const navtool_router_exclusion_zone_v7* zones;
    uint64_t zone_count;
    const navtool_router_exclusion_polygon_v7* polygons;
    uint64_t polygon_count;
    const navtool_router_exclusion_ring_v7* holes;
    uint64_t hole_count;
    const navtool_router_coordinate_v1* vertices;
    uint64_t vertex_count;
    navtool_router_provider_metadata_v7 metadata;
} navtool_router_exclusion_settings_v7;

/*
 * The complete opt-in Stage 3 environment. A null pointer, or a payload with
 * every provider unconfigured, reproduces the ABI-v6 arithmetic exactly.
 */
typedef struct navtool_router_environment_v7 {
    int32_t sampling;
    int32_t reserved;
    navtool_router_current_settings_v7 currents;
    navtool_router_wave_settings_v7 waves;
    navtool_router_landmask_settings_v7 land;
    navtool_router_exclusion_settings_v7 exclusions;
} navtool_router_environment_v7;

/*
 * Adds the optional Stage 3 environment to the v6 configuration-driven entry
 * point. Passing a null environment is equivalent to calling
 * navtool_router_calculate_route_streaming_v6 with the same arguments, and
 * produces byte-identical route JSON.
 *
 * Environment pointers are borrowed for the duration of the call only.
 * Contradictory configuration returns
 * NAVTOOL_ROUTER_STATUS_INVALID_ENVIRONMENT_V7 before any search begins, and
 * unusable provider data under a fail-route policy returns
 * NAVTOOL_ROUTER_STATUS_ENVIRONMENT_DATA_UNAVAILABLE_V7.
 */
NAVTOOL_ROUTER_BRIDGE_API navtool_router_status_v1
navtool_router_calculate_route_streaming_v7(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    const navtool_router_options_v6* options,
    const navtool_router_environment_v7* environment,
    navtool_router_progress_callback_v6 on_progress,
    void* progress_user_data,
    navtool_router_segment_eligibility_callback_v1 is_segment_eligible,
    void* segment_eligibility_user_data,
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
