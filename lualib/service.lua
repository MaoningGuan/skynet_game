local skynet = require "skynet"
require "skynet.manager"
local cluster = require "skynet.cluster"

local M = {
    -- 类型和id
    name = "",
    id = 0,
    -- 回调函数
    exit = nil,
    init = nil,
    -- 分发方法
    resp = {},
}

function traceback(error)
    skynet.error(tostring(error))
    skynet.error(debug.traceback())
end

local dispatch = function (session, address, cmd, ...)
    local fun = M.resp[cmd]
    if not fun then
        skynet.ret()
        return
    end

    local ret = table.pack(xpcall(fun, traceback, address, ...))
    local is_ok = ret[1]
    if not is_ok then
        skynet.ret()
        return
    end

    skynet.retpack(table.unpack(ret, 2))
end

function init()
    skynet.dispatch("lua", dispatch)
    if M.init then
        M.init()
    end
end

function M.start(name, id, ...)
    M.name = name
    M.id = tonumber(id)
    skynet.register(name..id)
    skynet.start(init)
end

---call方法封装
---@param node string 接收方所在的节点
---@param src string 接收方的服务名
---@param ... unknown
---@return unknown
function M.call(node, src, ...)
    local my_node = skynet.getenv('node')
    if node == my_node then
        return skynet.call(src, 'lua', ...)
    else
        return cluster.call(node, src, ...)
    end
end

---send方法封装
---@param node string 接收方所在的节点
---@param src string 接收方的服务名
---@param ... unknown
---@return unknown
function M.send(node, src, ...)
    local my_node = skynet.getenv('node')
    if node == my_node then
        return skynet.send(src, 'lua', ...)
    else
        return cluster.send(node, src, ...)
    end
end

return M