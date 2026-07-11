local RemoteSpy = {}
local Remote = import("objects/Remote")

local requiredMethods = {
    ["checkCaller"] = true,
    ["newCClosure"] = true,
    ["hookFunction"] = true,
    ["hookMetaMethod"] = true,
    ["isReadOnly"] = true,
    ["setReadOnly"] = true,
    ["getInfo"] = true,
    ["getMetatable"] = true,
    ["setClipboard"] = true,
    ["getNamecallMethod"] = true,
    ["getCallingScript"] = true,
}

local cloneRef = cloneref or function(obj)
    return obj
end

local cloneFunc = clonefunction or function(fn)
    return fn
end

local IsA = game.IsA
local lower = string.lower

local remoteMethods = {
    FireServer = true,
    InvokeServer = true,
    Fire = true,
    Invoke = true
}

local remotesViewing = {
    RemoteEvent = true,
    UnreliableRemoteEvent = true,
    RemoteFunction = false,
    BindableEvent = false,
    BindableFunction = false
}

local currentRemotes = {}

local remoteDataEvent = Instance.new("BindableEvent")
local eventSet = false

local function connectEvent(callback)
    remoteDataEvent.Event:Connect(callback)

    if not eventSet then
        eventSet = true
    end
end

local function deepclone(value, copies)
    copies = copies or {}

    if type(value) == "table" then
        if copies[value] then
            return copies[value]
        end

        local copy = {}
        copies[value] = copy

        for i, v in next, value do
            copy[deepclone(i, copies)] = deepclone(v, copies)
        end

        return copy
    end

    if typeof(value) == "Instance" then
        return cloneRef(value)
    end

    return value
end

local function isCyclicTable(tbl)
    local checked = {}

    local function searchTable(tableToSearch)
        table.insert(checked, tableToSearch)

        for _, v in next, tableToSearch do
            if type(v) == "table" then
                if table.find(checked, v) then
                    return true
                end

                if searchTable(v) then
                    return true
                end
            end
        end
    end

    return searchTable(tbl)
end

local function isRemoteClass(className, method)
    method = lower(method)

    if (className == "RemoteEvent" or className == "UnreliableRemoteEvent") and method == "fireserver" then
        return true
    elseif className == "RemoteFunction" and method == "invokeserver" then
        return true
    elseif className == "BindableEvent" and method == "fire" then
        return true
    elseif className == "BindableFunction" and method == "invoke" then
        return true
    end

    return false
end

local function normalizeMethod(method)
    if method == "fireServer" then
        return "FireServer"
    elseif method == "invokeServer" then
        return "InvokeServer"
    elseif method == "fire" then
        return "Fire"
    elseif method == "invoke" then
        return "Invoke"
    end

    return method
end

local function isWatchedRemote(instance)
    return IsA(instance, "RemoteEvent")
        or IsA(instance, "RemoteFunction")
        or IsA(instance, "UnreliableRemoteEvent")
        or IsA(instance, "BindableEvent")
        or IsA(instance, "BindableFunction")
end

local function handleRemote(instance, method, ...)
    if typeof(instance) ~= "Instance" then
        return false, false
    end

    local remoteInstance = cloneRef(instance)
    local className = remoteInstance.ClassName
    method = normalizeMethod(method)

    if not remotesViewing[className] or remoteInstance == remoteDataEvent then
        return false, false
    end

    if not remoteMethods[method] or not isRemoteClass(className, method) then
        return false, false
    end

    local vargs = { select(2, ...) }

    if isCyclicTable(vargs) then
        return true, false
    end

    local remote = currentRemotes[remoteInstance]

    if not remote then
        remote = Remote.new(remoteInstance)
        currentRemotes[remoteInstance] = remote
    end

    local remoteIgnored = remote.Ignored
    local remoteBlocked = remote.Blocked
    local argsIgnored = remote:AreArgsIgnored(vargs)
    local argsBlocked = remote:AreArgsBlocked(vargs)
    local blocked = remoteBlocked or argsBlocked

    if eventSet and (not remoteIgnored and not argsIgnored) then
        local call = {
            script = getCallingScript((PROTOSMASHER_LOADED ~= nil and 2) or nil),
            args = deepclone(vargs),
            func = getInfo(3).func
        }

        remote:IncrementCalls(call)
        remoteDataEvent:Fire(remoteInstance, call)
    end

    return true, blocked
end

local originalNamecall

local newNamecall = newCClosure(function(...)
    local method = getNamecallMethod()

    if method and (
        method == "FireServer" or method == "fireServer"
        or method == "InvokeServer" or method == "invokeServer"
        or method == "Fire" or method == "fire"
        or method == "Invoke" or method == "invoke"
    ) then
        local instance = ...

        if typeof(instance) == "Instance" then
            local remoteInstance = cloneRef(instance)

            if isWatchedRemote(remoteInstance) then
                local _, blocked = handleRemote(instance, method, ...)

                if blocked then
                    return
                end
            end
        end
    end

    return originalNamecall(...)
end)

local function makeDirectHook(methodName, originalMethod)
    return newCClosure(function(...)
        local instance = ...

        if typeof(instance) == "Instance" then
            local remoteInstance = cloneRef(instance)

            if isWatchedRemote(remoteInstance) then
                local _, blocked = handleRemote(instance, methodName, ...)

                if blocked then
                    return
                end
            end
        end

        return originalMethod(...)
    end)
end

local originalEvent = Instance.new("RemoteEvent").FireServer
local originalFunction = Instance.new("RemoteFunction").InvokeServer
local originalBindableEvent = Instance.new("BindableEvent").Fire
local originalBindableFunction = Instance.new("BindableFunction").Invoke

local originalUnreliableEvent
local hasUnreliableRemote = pcall(function()
    originalUnreliableEvent = Instance.new("UnreliableRemoteEvent").FireServer
end)

local newFireServer = makeDirectHook("FireServer", originalEvent)
local newInvokeServer = makeDirectHook("InvokeServer", originalFunction)
local newBindableFire = makeDirectHook("Fire", originalBindableEvent)
local newBindableInvoke = makeDirectHook("Invoke", originalBindableFunction)
local newUnreliableFireServer = hasUnreliableRemote and makeDirectHook("FireServer", originalUnreliableEvent) or nil

local synv3 = false

if syn and identifyexecutor then
    local _, version = identifyexecutor()

    if version and version:sub(1, 2) == "v3" then
        synv3 = true
    end
end

local oth = syn and syn.oth
local synHook = oth and oth.hook

if synv3 and synHook then
    originalNamecall = synHook(getMetatable(game).__namecall, cloneFunc(newNamecall))
    originalEvent = synHook(originalEvent, cloneFunc(newFireServer))
    originalFunction = synHook(originalFunction, cloneFunc(newInvokeServer))
    originalBindableEvent = synHook(originalBindableEvent, cloneFunc(newBindableFire))
    originalBindableFunction = synHook(originalBindableFunction, cloneFunc(newBindableInvoke))

    if hasUnreliableRemote then
        originalUnreliableEvent = synHook(originalUnreliableEvent, cloneFunc(newUnreliableFireServer))
    end
else
    originalNamecall = hookMetaMethod(game, "__namecall", cloneFunc(newNamecall))
    originalEvent = hookFunction(originalEvent, cloneFunc(newFireServer))
    originalFunction = hookFunction(originalFunction, cloneFunc(newInvokeServer))
    originalBindableEvent = hookFunction(originalBindableEvent, cloneFunc(newBindableFire))
    originalBindableFunction = hookFunction(originalBindableFunction, cloneFunc(newBindableInvoke))

    if hasUnreliableRemote then
        originalUnreliableEvent = hookFunction(originalUnreliableEvent, cloneFunc(newUnreliableFireServer))
    end
end

if type(originalNamecall) ~= "function" then
    originalNamecall = function(...)
        return ...
    end
end

oh.Hooks[originalEvent] = newFireServer
oh.Hooks[originalFunction] = newInvokeServer
oh.Hooks[originalBindableEvent] = newBindableFire
oh.Hooks[originalBindableFunction] = newBindableInvoke

if hasUnreliableRemote then
    oh.Hooks[originalUnreliableEvent] = newUnreliableFireServer
end

RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.RequiredMethods = requiredMethods

return RemoteSpy
