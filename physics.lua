local Physics = {}


local historyPool = {}


-- A `sync` is a serialization of frequently-varying object state (such as a body's position or velocity)

local function readBodySync(body)
    local x, y = body:getPosition()
    local vx, vy = body:getLinearVelocity()
    local a = body:getAngle()
    local va = body:getAngularVelocity()
    return x, y, vx, vy, a, va
end

local function writeBodySync(body, x, y, vx, vy, a, va)
    body:setPosition(x, y)
    body:setLinearVelocity(vx, vy)
    body:setAngle(a)
    body:setAngularVelocity(va)
end

local function writeInterpolatedBodySync(body, interpolatedTick, history)
    -- Find closest ticks before and after the one we want to interpolate to
    local beforeTick, afterTick
    for i in pairs(history) do
        if i < interpolatedTick and (not beforeTick or i > beforeTick) then
            beforeTick = i
        end
        if i >= interpolatedTick and (not afterTick or i < afterTick) then
            afterTick = i
        end
    end
    if beforeTick and afterTick then
        local f = (interpolatedTick - beforeTick) / (afterTick - beforeTick)
        local beforeSync, afterSync = history[beforeTick], history[afterTick]
        local interpolatedSync = {}
        for i = 1, #beforeSync do
            interpolatedSync[i] = beforeSync[i] + f * (afterSync[i] - beforeSync[i])
        end
        writeBodySync(body, unpack(interpolatedSync))
        return true
    end
    return false
end


-- Each physics method has three parts: a message kind definition, a message receiver, and a message send wrapper
function Physics:_defineMethod(methodName, opts)
    local kind = self.kindPrefix .. methodName

    -- Kind definition
    if not self.game.receivers[kind] then -- Don't redefine
        self.game:defineMessageKind(kind, opts.defaultSendParams)
    end

    -- Receiver
    self.game.receivers[kind] = assert(opts.receiver,
        '_defineMethod: need to define a receiver for `' .. methodName .. '`')

    -- Sender -- default sender just forwards parameters
    self[methodName] = (opts.sender and opts.sender(kind)) or function(_, ...)
        self.game:send({ kind = kind }, ...)
    end
end


-- All `love.physics.new<X>` as `Physics:new<X>`, returns object id
local CONSTRUCTOR_NAMES = {
    'newBody', 'newChainShape', 'newCircleShape', 'newDistanceJoint',
    'newEdgeShape', 'newFixture', 'newFrictionJoint', 'newGearJoint',
    'newMotorJoint', 'newMouseJoint', 'newPolygonShape', 'newPrismaticJoint',
    'newPulleyJoint', 'newRectangleShape', 'newRevoluteJoint', 'newRopeJoint',
    'newWeldJoint', 'newWheelJoint', 'newWorld',
}

-- All `:<foo>` as `Physics:<foo>` with object id as first param
local RELIABLE_METHOD_NAMES = {
    'setActive', 'setAngle', 'setAngularDamping', 'setAngularOffset',
    'setAngularVelocity', 'setAwake', 'setBullet', 'setCategory',
    'setContactFilter', 'setCorrectionFactor', 'setDampingRatio', 'setDensity',
    'setEnabled', 'setFilterData', 'setFixedRotation', 'setFrequency',
    'setFriction', 'setGravity', 'setGravityScale', 'setGroupIndex', 'setInertia',
    'setLength', 'setLimits', 'setLimitsEnabled', 'setLinearDamping',
    'setLinearOffset', 'setLinearVelocity', 'setLowerLimit', 'setMask', 'setMass',
    'setMassData', 'setMaxForce', 'setMaxLength', 'setMaxMotorForce',
    'setMaxMotorTorque', 'setMaxTorque', 'setMotorEnabled', 'setMotorSpeed',
    'setNextVertex', 'setPoint', 'setPosition', 'setPreviousVertex', 'setRadius',
    'setRatio', 'setRestitution', 'setSensor', 'setSleepingAllowed',
    'setSpringDampingRatio', 'setSpringFrequency', 'setTangentSpeed', 'setTarget',
    'setType', 'setUpperLimit', 'setX', 'setY',
}


function Physics.new(opts)
    local self = setmetatable({}, { __index = Physics })


    -- Options

    self.game = assert(opts.game, 'Physics.new: need `opts.game`')
    local game = self.game -- Keep an upvalue for closures to use

    self.reliableChannel = opts.reliableChannel or 100
    self.serverSyncsChannel = opts.serverSyncsChannel or 101
    self.clientSyncsChannel = opts.clientSyncsChannel or 102

    self.serverSyncsRate = opts.serverSyncsRate or 10
    self.clientSyncsRate = opts.clientSyncsRate or 30

    self.updateRate = opts.updateRate or 144
    self.historyRate = opts.historyRate or 12
    self.historySize = opts.historySize or (self.updateRate * 0.5)
    self.interpolationDelay = opts.interpolationDelay or 0.08
    self.softOwnershipSetDelay = opts.softOwnershipSetDelay or 0.8

    self.kindPrefix = opts.kindPrefix or 'physics_'


    -- Object data tables

    self.idToObject = {}

    self.idToWorld = {}

    self.objectDatas = {}

    self.ownerIdToObjects = {}
    setmetatable(self.ownerIdToObjects, {
        __index = function(t, k)
            local v = {}
            t[k] = v
            return v
        end,
    })


    -- Other state

    self.lastNetworkIssueTime = nil


    -- Generated constructors

    for _, methodName in ipairs(CONSTRUCTOR_NAMES) do
        self:_defineMethod(methodName, {
            defaultSendParams = {
                -- Only server can construct objects
                from = 'server',

                -- Constructors can't be missed
                reliable = true,
                channel = self.reliableChannel,

                -- Everyone should know about a construction
                to = 'all',
                selfSend = true,
                forward = true,
            },

            receiver = function(_, time, id, ...)
                (function (...)
                    if self.idToObject[id] then
                        error(methodName .. ': object with this id already exists')
                    end
                    local obj
                    local succeeded, err = pcall(function(...)
                        obj = love.physics[methodName](...)
                    end, ...)
                    if succeeded then
                        self.idToObject[id] = obj
                        local objectData = { id = id }
                        if methodName == 'newBody' then
                            objectData.ownerId = nil
                            objectData.lastSetOwnerTickCount = 0
                            objectData.clientSyncHistory = {}
                            if self.game.server then
                                objectData.history = {}
                            end
                        end
                        if methodName == 'newWorld' then
                            self.idToWorld[id] = obj
                            objectData.updateTimeRemaining = 0
                            objectData.tickCount = 0
                            objectData.nextRewindFrom = nil
                            obj:setCallbacks(self._beginContact, self._endContact, self._preSolve, self._postSolve)
                            if self.game.client then
                                objectData.lastServerSyncTime = nil
                            end
                        end
                        self.objectDatas[obj] = objectData
                    else
                        error(methodName .. ': ' .. err)
                    end
                end)(self:_resolveIds(...))
            end,

            sender = function(kind)
                return function(_, ...)
                    local id = game:generateId()
                    game:send({ kind = kind }, id, ...)
                    return id
                end
            end,
        })
    end


    -- Generated reliable methods

    for _, methodName in ipairs(RELIABLE_METHOD_NAMES) do
        self:_defineMethod(methodName, {
            defaultSendParams = {
                -- Reliable method calls can't be missed
                reliable = true,
                channel = self.reliableChannel,

                -- Everyone should know about a reliable method call
                to = 'all',
                selfSend = true,
                forward = true,
            },

            receiver = function(_, time, id, ...)
                (function (...)
                    local obj = self.idToObject[id]
                    if not obj then
                        error(methodName .. ': no / bad `id` given as first parameter')
                    end
                    local succeeded, err = pcall(function(...)
                        obj[methodName](obj, ...)
                    end, ...)
                    if not succeeded then
                        error(methodName .. ': ' .. err)
                    end
                end)(self:_resolveIds(...))
            end,
        })
    end


    -- Object destruction

    self:_defineMethod('destroyObject', {
        defaultSendParams = {
            -- Only server can destroy objects
            from = 'server',

            -- Destructions can't be missed
            reliable = true,
            channel = self.reliableChannel,

            -- Everyone should know about a destruction
            to = 'all',
            selfSend = true,
            forward = true,
        },

        receiver = function(_, time, id)
            local obj = self.idToObject[id]
            if not obj then
                error('destroyObject: no / bad `id`')
            end

            local function clearMapEntries(id, obj)
                self.objectDatas[obj] = nil
                self.idToWorld[id] = nil
                self.idToObject[id] = nil
            end

            -- Visit associated objects
            if obj:typeOf('Body') then
                for _, fixture in pairs(obj:getFixtures()) do
                    local fixtureData = self.objectDatas[fixture]
                    if fixtureData then
                        clearMapEntries(fixtureData.id, fixture)
                    end
                end
                for _, joint in pairs(obj:getJoints()) do
                    local jointData = self.objectDatas[joint]
                    if jointData then
                        handleId(jointData.id, joint)
                    end
                end
            end

            -- Visit this object
            local objectData = self.objectDatas[obj]
            if objectData.ownerId then
                self.ownerIdToObjects[objectData.ownerId][obj] = nil
            end
            local history = objectData.history
            if history then -- Return history entries to pool
                for _, entry in pairs(history) do
                    table.insert(historyPool, entry)
                end
            end
            clearMapEntries(id, obj)

            -- Call actual object destructor (calls destructors for associated objects automatically)
            if obj.destroy then
                obj:destroy()
            else
                obj:release()
            end
        end,
    })


    -- Object ownership

    self:_defineMethod('setOwner', {
        defaultSendParams = {
            -- Setting owner can't be missed
            reliable = true,
            channel = self.reliableChannel,

            -- Everyone should know about setting owner
            to = 'all',
            selfSend = true,
            forward = true,
        },

        receiver = function(_, time, tickCount, id, newOwnerId, strongOwned, ...)
            local obj = self.idToObject[id]
            if not obj then
                error('setOwner: no / bad `id`')
            end

            local objectData = self.objectDatas[obj]

            if newOwnerId == nil then -- Removing owner
                if objectData.ownerId == nil then
                    return
                else
                    self.ownerIdToObjects[objectData.ownerId][obj] = nil
                    objectData.ownerId = nil
                end
            else -- Setting owner
                if objectData.ownerId ~= nil then -- Already owned by someone?
                    if objectData.ownerId == newOwnerId then
                        return -- Already owned by this client, nothing to do
                    else
                        self.ownerIdToObjects[objectData.ownerId][obj] = nil
                        objectData.ownerId = nil
                    end
                end

                self.ownerIdToObjects[newOwnerId][obj] = true
                objectData.ownerId = newOwnerId
            end

            if strongOwned then
                objectData.strongOwned = true
            else
                objectData.strongOwned = nil
            end

            if select('#', ...) > 0 then
                local worldData = self.objectDatas[obj:getWorld()]

                objectData.clientSyncHistory = {}

                local interpolatedTick = math.floor(worldData.tickCount - self.interpolationDelay * self.updateRate)
                objectData.clientSyncHistory[interpolatedTick] = { readBodySync(obj) }
                objectData.clientSyncHistory[tickCount] = { ... }
            end

            objectData.lastSetOwnerTickCount = tickCount
        end,

        sender = function(kind)
            return function(_, id, ...)
                local obj = self.idToObject[id]
                game:send({ kind = kind }, obj and self.objectDatas[obj:getWorld()].tickCount or 0, id, ...)
            end
        end,
    })


    -- Server syncs

    self:_defineMethod('serverSyncs', {
        defaultSendParams = {
            -- Only server can send server syncs
            from = 'server',

            -- Server sends syncs to everyone
            to = 'all',

            -- This happens constantly at a high rate
            reliable = false,
            channel = self.serverSyncsChannel,
            rate = self.serverSyncsRate,

            -- Server doesn't need to receive its own syncs
            selfSend = false,
        },

        receiver = function(game, time, tickCount, worldId, syncs)
            -- Get world
            local world = self.idToObject[worldId]
            if not world then
                return
            end
            local worldData = self.objectDatas[world]
            worldData.lastServerSyncTime = math.max(worldData.lastServerSyncTime or time, time)

            -- Save state of objects we own
            local saves = {}
            for obj in pairs(self.ownerIdToObjects[self.game.clientId]) do
                saves[obj] = { readBodySync(obj) }
            end

            -- Actually apply the syncs
            for id, sync in pairs(syncs) do
                local obj = self.idToObject[id]
                if obj and self.objectDatas[obj].clientId ~= self.game.clientId then
                    writeBodySync(obj, unpack(sync))
                end
            end

            -- We'll need to catch it up to the current tick
            if tickCount <= worldData.tickCount then
                local latestTickCount = worldData.tickCount
                worldData.tickCount = tickCount
                while worldData.tickCount < latestTickCount do
                    self:_tickWorld(world, worldData)
                end
            else
                worldData.tickCount = tickCount
            end

            -- Restore state of objects we own
            for obj, save in pairs(saves) do
                writeBodySync(obj, unpack(save))
            end
        end,
    })


    -- Client syncs

    self:_defineMethod('clientSyncs', {
        defaultSendParams = {
            -- Only client can send client syncs
            from = 'client',

            -- This happens constantly at a high rate
            reliable = false,
            channel = self.clientSyncsChannel,
            rate = self.clientSyncsRate,

            -- Client syncs are forwarded to all
            forward = true,

            -- Client doesn't need to receive its own syncs
            selfSend = false,
        },

        receiver = function(game, time, clientId, tickCount, worldId, syncs)
            -- Get world
            local world = self.idToObject[worldId]
            if not world then
                return
            end
            local worldData = self.objectDatas[world]

            -- If the sync is too old, just drop
            if tickCount <= worldData.tickCount + 1 - self.historySize then
                return
            end

            -- Save syncs to history
            for id, sync in pairs(syncs) do
                local obj = self.idToObject[id]
                if obj then
                    local objectData = self.objectDatas[obj]
                    if objectData.ownerId == clientId then
                        objectData.clientSyncHistory[tickCount] = { unpack(sync) }
                    end
                end
            end

            -- Server will rewind and recompute history
            if self.game.server and tickCount < worldData.tickCount then
                worldData.nextRewindFrom = math.min(worldData.nextRewindFrom or worldData.tickCount, tickCount)
            end
        end,
    })


    -- Collision callbacks

    if self.game.client then
        function self._postSolve(fixture1, fixture2, contact)
            local body1 = fixture1:getBody()
            local body2 = fixture2:getBody()

            if body1:getType() == 'static' or body2:getType() == 'static' then
                return
            end

            local worldData = self.objectDatas[body1:getWorld()]

            local d1 = self.objectDatas[body1]
            local d2 = self.objectDatas[body2]

            if d1 and d2 then
                local function check(d1, d2)
                    if d1.ownerId ~= nil  and not d2.strongOwned then
                        if d2.ownerId ~= d1.ownerId then
                            if worldData.tickCount - d2.lastSetOwnerTickCount >= self.softOwnershipSetDelay * self.updateRate then
                                if d1.strongOwned or d1.lastSetOwnerTickCount > d2.lastSetOwnerTickCount then
                                    self:setOwner(d2.id, d1.ownerId, false, readBodySync(body2))
                                end
                            end
                        end
                    end
                end
                check(d1, d2)
                check(d2, d1)
            end
        end

        function self._endContact(fixture1, fixture2, contact)
        end
    end


    return self
end


function Physics:_resolveIds(firstArg, ...)
    local firstResult = self.idToObject[firstArg] or firstArg
    if select('#', ...) == 0 then
        return firstResult
    end
    return firstResult, self:_resolveIds(...)
end


function Physics:syncNewClient(opts)
    local clientId = assert(opts.clientId, 'syncNewClient: need `opts.clientId`')

    local function send(methodName, ...) -- Shorthand to send messages to this client only
        self.game:send({
            kind = self.kindPrefix .. methodName,

            -- Send only to this client
            to = clientId,
            selfSend = false,

            -- Send everything in order
            channel = opts.channel or self.reliableChannel,
        }, ...)
    end

    local visited = {}

    local temporaryIds = {} -- Ids of temporary objects -- should just be shapes

    local function visit(obj, id) -- Send constructor + setters for one object, visiting its dependencies first
        if visited[obj] then
            return visited[obj]
        end

        if not id then
            local objectData = self.objectDatas[obj]
            if objectData then
                id = objectData.id
            else
                id = self.game:generateId()
                temporaryIds[id] = true
            end
        end

        visited[obj] = id

        if obj:typeOf('World') then
            local gravityX, gravityY = obj:getGravity()
            send('newWorld', id, gravityX, gravityY, obj:isSleepingAllowed())
        elseif obj:typeOf('Body') then
            send('newBody', id, visit(obj:getWorld()), obj:getX(), obj:getY(), obj:getType())
            send('setMassData', id, obj:getMassData())
            send('setFixedRotation', id, obj:isFixedRotation())

            send('setAngle', id, obj:getAngle())

            send('setLinearVelocity', id, obj:getLinearVelocity())
            send('setAngularVelocity', id, obj:getAngularVelocity())

            send('setLinearDamping', id, obj:getLinearDamping())
            send('setAngularDamping', id, obj:getAngularDamping())

            send('setAwake', id, obj:isAwake())
            send('setActive', id, obj:isActive())
            send('setBullet', id, obj:isBullet())
            send('setGravityScale', id, obj:getGravityScale())
        elseif obj:typeOf('Fixture') then
            send('newFixture', id, visit(obj:getBody()), visit(obj:getShape()), obj:getDensity())
            send('setFilterData', id, obj:getFilterData())
            send('setFriction', id, obj:getFriction())
            send('setRestitution', id, obj:getRestitution())
            send('setSensor', id, obj:isSensor())
        elseif obj:typeOf('Shape') then
            local shapeType = obj:getType()
            if shapeType == 'circle' then
                local x, y = obj:getPoint()
                send('newCircleShape', id, x, y, obj:getRadius())
            elseif shapeType == 'polygon' then
                send('newPolygonShape', id, obj:getPoints())
            elseif shapeType == 'edge' then
                send('newEdgeShape', id, obj:getPoints())
                send('setPreviousVertex', id, obj:getPreviousVertex())
                send('setNextVertex', id, obj:getNextVertex())
            elseif shapeType == 'chain' then
                send('newChainShape', id, obj:getPoints())
                send('setPreviousVertex', id, obj:getPreviousVertex())
                send('setNextVertex', id, obj:getNextVertex())
            end
        end
        -- TODO(nikki): Handle joints!

        return id
    end

    for id, obj in pairs(self.idToObject) do -- Visit all physics objects
        visit(obj, id)
    end

    for id in pairs(temporaryIds) do -- Destroy temporary objects created by visiting
        send('destroyObject', id)
    end

    for ownerId, objects in pairs(self.ownerIdToObjects) do -- Send ownerships
        for obj in pairs(objects) do
            local objectData = self.objectDatas[obj]
            send('setOwner', objectData.lastSetOwnerTickCount, objectData.id, ownerId, objectData.strongOwned)
        end
    end
end


function Physics:objectForId(id)
    return self.idToObject[id]
end

function Physics:idForObject(obj)
    local objectData = self.objectDatas[obj]
    if objectData then
        return objectData.id
    end
    return nil
end


function Physics:getWorld()
    local resultId, resultWorld
    for id, world in pairs(self.idToWorld) do
        if resultId then
            error('getWorld: there are multiple worlds -- you will need to keep track of their ids yourself')
        end
        resultId, resultWorld = id, world
    end
    return resultId, resultWorld
end

function Physics:_tickWorld(world, worldData)
    world:update(1 / self.updateRate)
    worldData.tickCount = worldData.tickCount + 1

    -- Interpolate objects owned by others
    for ownerId, objs in pairs(self.ownerIdToObjects) do
        if ownerId ~= self.game.clientId then
            for obj in pairs(objs) do
                local objectData = self.objectDatas[obj]
                local clientSyncHistory = objectData.clientSyncHistory
                if next(clientSyncHistory) ~= nil then
                    -- Clear out old history
                    for i in pairs(clientSyncHistory) do
                        if i <= worldData.tickCount - self.historySize then
                            clientSyncHistory[i] = nil
                        end
                    end

                    -- Interpolate
                    local interpolationDelay = self.interpolationDelay
                    if not objectData.strongOwned then
                        interpolationDelay = 0.8 * interpolationDelay
                    end
                    local interpolatedTick = math.floor(worldData.tickCount - interpolationDelay * self.updateRate)
                    writeInterpolatedBodySync(obj, interpolatedTick, clientSyncHistory)
                end
            end
        end
    end

    -- Server keeps full history
    if self.game.server then
        for _, body in ipairs(world:getBodies()) do
            local objectData = self.objectDatas[body]
            if objectData then
                local history = objectData.history

                -- Clear old history, returning to pool
                if history[worldData.tickCount - self.historySize] then
                    table.insert(historyPool, history[worldData.tickCount - self.historySize])
                    history[worldData.tickCount - self.historySize] = nil
                end

                -- Write to history if not static or sleeping
                if worldData.tickCount % self.historyRate == 0 and body:isAwake() and body:getType() ~= 'static' then
                    local pooled = table.remove(historyPool)
                    if pooled then
                        pooled[1], pooled[2], pooled[3], pooled[4], pooled[5], pooled[6] = readBodySync(body)
                        history[worldData.tickCount] = pooled
                    else
                        history[worldData.tickCount] = { readBodySync(body) }
                    end
                end
            end
        end
    end
end

function Physics:updateWorld(worldId, dt)
    local world = assert(self.idToObject[worldId], 'updateWorld: no world with this id')
    local worldData = self.objectDatas[world]

    -- If server, perform any outstanding rewinds we need to do
    if self.game.server and worldData.nextRewindFrom then
        -- Rewind
        for _, body in ipairs(world:getBodies()) do
            if body:getType() ~= 'static' then
                local objectData = self.objectDatas[body]
                if objectData then
                    local history = objectData.history
                    local clientSyncHistory = objectData.clientSyncHistory

                    -- Interpolate from client syncs, or use full history if no client sync interpolation worked
                    if not writeInterpolatedBodySync(body, worldData.nextRewindFrom, clientSyncHistory) then
                        writeInterpolatedBodySync(body, worldData.nextRewindFrom, history)
                    end
                end
            end
        end

        -- Play back
        local latestTickCount = worldData.tickCount
        worldData.tickCount = worldData.nextRewindFrom
        while worldData.tickCount < latestTickCount do
            self:_tickWorld(world, worldData)
        end
        worldData.nextRewindFrom = nil
    end

    -- Catch up world to current time
    --if self.game.client and (not worldData.lastServerSyncTime or
    --        self.game.time - worldData.lastServerSyncTime > 3 * (1 / self.serverSyncsRate)) then
    --    if worldData.lastServerSyncTime then
    --        self.lastNetworkIssueTime = love.timer.getTime()
    --    end
    --    return false
    --end
    worldData.updateTimeRemaining = worldData.updateTimeRemaining + dt
    while worldData.updateTimeRemaining >= 1 / self.updateRate do
        self:_tickWorld(world, worldData)
        worldData.updateTimeRemaining = worldData.updateTimeRemaining - 1 / self.updateRate
    end
    return true
end

function Physics:sendSyncs(worldId)
    local world = assert(self.idToObject[worldId], 'updateWorld: no world with this id')

    if self.game.server then -- Server version
        local syncs = {}
        for _, body in ipairs(world:getBodies()) do
            if body:isAwake() and body:getType() ~= 'static' then
                local objectData = self.objectDatas[body]
                if objectData then -- Make sure it's a network-tracked body
                    syncs[objectData.id] = { readBodySync(body) }
                end
            end
        end
        self:serverSyncs(self.objectDatas[world].tickCount, worldId, syncs)
    end

    if self.game.client then -- Client version
        local syncs = {}
        for obj in pairs(self.ownerIdToObjects[self.game.clientId]) do
            local objectData = self.objectDatas[obj]

            if self.objectDatas[obj:getWorld()].id == worldId then
                syncs[objectData.id] = { readBodySync(obj) }
            end

            if not objectData.strongOwned and not obj:isAwake() then
                self:setOwner(objectData.id, nil, false)
            end
        end
        self:clientSyncs(self.game.clientId, self.objectDatas[world].tickCount, worldId, syncs)
    end
end


function Physics:getOwner(id)
    local objectData = self.objectDatas[self.idToObject[id]]
    if objectData then
        return objectData.ownerId, objectData.strongOwned
    end
end


function Physics:networkIssueDetected()
    return self.lastNetworkIssueTime and love.timer.getTime() - self.lastNetworkIssueTime < 1.5
end


return Physics
