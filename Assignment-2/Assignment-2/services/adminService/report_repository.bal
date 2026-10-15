type ReportStore record {|
    table<RestaurantStatistics> key(restaurantId) restaurantStatistics;
    table<DeliveryPerformance> key(driverId) deliveryPerformance;
|};

isolated ReportStore reportStore = {
    restaurantStatistics: table [],
    deliveryPerformance: table []
};

// Upserts a restaurant projection supplied by future Kafka consumers.
isolated function memorySaveRestaurantStatistics(RestaurantStatistics statistics)
        returns RestaurantStatistics|error {
    lock {
        if statistics.totalOrders < 0 || statistics.completedOrders < 0 ||
                statistics.cancelledOrders < 0 || statistics.grossRevenue < 0d {
            return error("Restaurant statistics cannot contain negative values");
        }
        RestaurantStatistics storedStatistics = statistics.clone();
        if reportStore.restaurantStatistics.hasKey(storedStatistics.restaurantId) {
            _ = reportStore.restaurantStatistics.put(storedStatistics);
        } else {
            reportStore.restaurantStatistics.add(storedStatistics);
        }
        return storedStatistics.clone();
    }
}

// Upserts a delivery projection supplied by future Kafka consumers.
isolated function memorySaveDeliveryPerformance(DeliveryPerformance performance)
        returns DeliveryPerformance|error {
    lock {
        if performance.assignedDeliveries < 0 || performance.completedDeliveries < 0 ||
                performance.averageDeliveryMinutes < 0d {
            return error("Delivery performance cannot contain negative values");
        }
        DeliveryPerformance storedPerformance = performance.clone();
        if reportStore.deliveryPerformance.hasKey(storedPerformance.driverId) {
            _ = reportStore.deliveryPerformance.put(storedPerformance);
        } else {
            reportStore.deliveryPerformance.add(storedPerformance);
        }
        return storedPerformance.clone();
    }
}

isolated function memoryGetRestaurantStatistics() returns RestaurantStatistics[] {
    lock {
        return reportStore.restaurantStatistics.toArray().clone();
    }
}

isolated function memoryGetDeliveryPerformance() returns DeliveryPerformance[] {
    lock {
        return reportStore.deliveryPerformance.toArray().clone();
    }
}

// Aggregates the current projections into an inexpensive platform summary.
isolated function memoryGetPlatformSummary() returns PlatformSummary {
    lock {
        int totalOrders = 0;
        int completedOrders = 0;
        int cancelledOrders = 0;
        decimal grossRevenue = 0d;
        foreach RestaurantStatistics statistics in reportStore.restaurantStatistics {
            totalOrders += statistics.totalOrders;
            completedOrders += statistics.completedOrders;
            cancelledOrders += statistics.cancelledOrders;
            grossRevenue += statistics.grossRevenue;
        }
        int completedDeliveries = 0;
        foreach DeliveryPerformance performance in reportStore.deliveryPerformance {
            completedDeliveries += performance.completedDeliveries;
        }
        return {
            restaurantCount: reportStore.restaurantStatistics.length(),
            totalOrders,
            completedOrders,
            cancelledOrders,
            grossRevenue,
            activeDriverCount: reportStore.deliveryPerformance.length(),
            completedDeliveries
        };
    }
}

public isolated function clearReports() {
    lock {
        reportStore = {restaurantStatistics: table [], deliveryPerformance: table []};
    }
}

