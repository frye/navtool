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

#define NAVTOOL_ROUTER_BRIDGE_ABI_VERSION 1u

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
    NAVTOOL_ROUTER_STATUS_INTERNAL_ERROR_V1 = 10
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

NAVTOOL_ROUTER_BRIDGE_API uint32_t
navtool_router_bridge_abi_version_v1(void);

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

#ifdef __cplusplus
}
#endif

#endif
