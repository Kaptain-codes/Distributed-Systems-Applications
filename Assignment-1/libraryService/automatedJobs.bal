import ballerina/task;
import ballerina/time;

// Define a background service job
service class OverdueSchedulerJob {
    *task:Job;

    // This block of code executes automatically on the timer tick
    public isolated function execute() {
        lock {
            time:Utc currentTime = time:utcNow();

            foreach var asset in assetTable {
                boolean markedOverdue = false;

                // Scan through every schedule inside this asset
                foreach var schedule in asset.schedules {
                    if (schedule.scheduleStatus == ACTIVE || schedule.scheduleStatus == PENDING) && 
                       schedule.dueDate < currentTime {
                        
                        schedule.scheduleStatus = OVERDUE; // Mutate the state block
                        markedOverdue = true;
                    }
                }

                // If any schedule inside this asset is overdue, update the parent table
                if markedOverdue {
                    assetTable.put(asset);
                }
            }
        }
    }
}