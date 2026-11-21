--!strict
local TaskQueueEngine = {}

export type Job = {
	id: string,
	task: () -> (),
	delay: number?
}

local queue = {}
local isProcessing = false

-- Process queue with optional delay between executions to prevent server lag
local function processQueue()
	if isProcessing or #queue == 0 then return end
	isProcessing = true

	while #queue > 0 do
		local job = table.remove(queue, 1) :: Job
		
		-- Execute the job safely
		local success, err = pcall(job.task)
		if not success then
			warn(`[TaskQueue] Job {job.id} failed: {err}`)
		end
		
		-- Yield to prevent frame drops if a delay is specified
		if job.delay and job.delay > 0 then
			task.wait(job.delay)
		else
			task.wait() -- Minimum yield to yield to the engine
		end
	end

	isProcessing = false
end

function TaskQueueEngine.enqueue(job: Job)
	table.insert(queue, job)
	-- Start processing if not already running
	if not isProcessing then
		task.spawn(processQueue)
	end
end

function TaskQueueEngine.clear()
	table.clear(queue)
	isProcessing = false
end

return TaskQueueEngine