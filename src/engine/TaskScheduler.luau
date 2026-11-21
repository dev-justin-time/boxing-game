--!strict
local TaskScheduler = {}

export type Task = {
	id: string,
	func: () -> (),
	delay: number,
	repeatCount: number, -- -1 for infinite
	currentIteration: number,
	nextFire: number,
}

local activeTasks: {[string]: Task} = {}
local isRunning = false

function TaskScheduler.schedule(id: string, delay: number, repeatCount: number, func: () -> ())
	activeTasks[id] = {
		id = id,
		func = func,
		delay = delay,
		repeatCount = repeatCount,
		currentIteration = 0,
		nextFire = os.clock() + delay,
	}
	
	if not isRunning then
		isRunning = true
		task.spawn(function()
			while next(activeTasks) do
				local currentTime = os.clock()
				for taskId, taskData in pairs(activeTasks) do
					if currentTime >= taskData.nextFire then
						task.spawn(taskData.func)
						
						taskData.currentIteration += 1
						if taskData.repeatCount == -1 or taskData.currentIteration < taskData.repeatCount then
							taskData.nextFire = currentTime + taskData.delay
						else
							activeTasks[taskId] = nil
						end
					end
				end
				task.wait() -- Single loop yields to engine
			end
			isRunning = false
		end)
	end
end

function TaskScheduler.cancel(id: string)
	activeTasks[id] = nil
end

function TaskScheduler.cancelAll()
	table.clear(activeTasks)
end

return TaskScheduler