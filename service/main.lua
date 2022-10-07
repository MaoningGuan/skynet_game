local skynet = require "skynet"
local runconfig = require "runconfig"

skynet.start(function ()
    -- 初始化
    skynet.uniqueservice('debug_console', 8000)
    local my_node = skynet.getenv("node")
    skynet.error('[start main]')

    -- 启动网关服务
    local gatewaycfg = runconfig[my_node].gateway
    for key, _ in pairs(gatewaycfg) do
        skynet.newservice('gateway', 'gateway', key)
    end

    -- 启动login服务
    local logincfg = runconfig[my_node].login
    for key, _ in pairs(logincfg) do
        skynet.newservice('login', 'login', key)
    end

    -- 退出自身
    skynet.exit()
end)