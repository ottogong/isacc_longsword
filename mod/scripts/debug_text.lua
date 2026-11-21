local Locale = include("scripts.locale")
local DebugText = {}
local font, ink
local chinese = {
    ["true"] = "是", ["false"] = "否", keyboard = "键鼠", unknown = "未知",
    LEFT = "左", RIGHT = "右", UP = "上", DOWN = "下", NONE = "无",
    IDLE = "待机", STARTUP = "起手", ACTIVE = "生效", RECOVERY = "后摇", HOLD = "保持",
    SHEATHED_FREE = "收刀", DRAWN_FREE = "持刀", SHEATHE_STARTUP = "纳刀起手",
    NORMAL = "直斩", THRUST = "戳刺", RISING = "上挑", CHARGE = "蓄力",
    SPIRIT = "气刃斩", SPIRIT_I = "气刃一", SPIRIT_II = "气刃二", SPIRIT_III = "气刃三",
    ROUND_SLASH = "大回旋", FORESIGHT = "见切", IAI = "大居合", SPECIAL_SHEATHE = "特殊纳刀",
    SHEATHED_STEP = "纳刀闪身", HELM_BREAKER = "登龙", SPIRIT_THRUST = "气刃突刺",
    THRUST_CYCLE = "刺挑", LOCKED = "锁定", FREE = "自由", ["not requested"] = "尚未尝试",
    OK = "就绪", EQUIPPED = "已装备", ALREADY_HELD = "已持有", POCKET_OCCUPIED = "口袋已占用",
    NO_RECENT_ATTACK = "近期未出招", BLADE_REQUIRED = "需要刃等级", STARTED = "已起手",
    BUFFERED = "已预输入", FINISHED = "已完成", MOVE = "移动", MOUSE_PRIMARY = "主攻键",
}

function DebugText.value(value)
    local raw = tostring(value)
    return Locale.isChinese() and chinese[raw] or raw
end

function DebugText.draw(text, x, y)
    if not Locale.isChinese() then
        Isaac.RenderText(text, x, y, 1, 1, 1, 1)
        return
    end
    if not font then
        font = Font()
        font:Load("font/cjk/lanapixel.fnt")
        ink = KColor(1, 1, 1, 1)
    end
    font:DrawStringUTF8(text, x, y, ink)
end

return DebugText
