local function animationFrames(activeStart, recoveryStart, frameCount, followupGrace)
    return {
        startup = activeStart, active = recoveryStart - activeStart, recovery = frameCount - recoveryStart,
        bufferThrough = frameCount, recentAttackFrames = frameCount + followupGrace,
    }
end

-- The game clip starts at frame 0, the 60 fps source at frame 1.
local function gameFrame(sourceFrame)
    return math.floor((sourceFrame - 1) / 2)
end

local function clipFrames(firstActive, firstRecovery, frameCount, followupGrace)
    -- Preserve the measured link: take the first update at or after the recovery cue.
    return animationFrames(gameFrame(firstActive), math.ceil((firstRecovery - 1) / 2), frameCount, followupGrace)
end

-- Foresight protects immediately; source frame 60 also begins its return cut.
local foresightFrames = animationFrames(0, gameFrame(101), 94, 36)
foresightFrames.firstHitFrame = gameFrame(60)

-- 108's guard trajectory peaks on source frames 19, 38 and 90.
local spiritIIIFrames = clipFrames(15, 101, 101, 30)
spiritIIIFrames.hitStarts = { spiritIIIFrames.startup, gameFrame(31), gameFrame(81) }

-- 308 guards through source frame 80. Keep the existing 15-tick damaging cut.
local iaiFrames = animationFrames(3, gameFrame(81), 89, 30)
iaiFrames.lastHitFrame = 14 -- Local to ACTIVE, i.e. game frames 3-17 inclusive.

-- 170–173 共用动作倍速，叠加面板射速。判定和姿势仍按原动画帧定位。
local helmSpeed = 1.2
local spiritThrustFrames = clipFrames(61, 91, 123, 30) -- 170 前冲源帧 61–90，挥空播到 245。
spiritThrustFrames.speed = helmSpeed
local helmJumpHeight = 58 -- 登龙离地高度（屏幕像素），原片约 46。
local helmFallSpeed = 5 -- 172 下落的位移和姿势共用这个倍速。
local takeoffTicks = math.ceil(47 / 2)
local fallSourceTicks = math.max(1, math.ceil(67 * math.max(0, helmJumpHeight) / 46))
local touchdown = takeoffTicks + math.ceil(fallSourceTicks / helmFallSpeed)
-- 173 starts on touchdown. Keep the original 15-tick slash, then finish the 115-frame landing.
local helmFrames = animationFrames(touchdown, touchdown + 15, touchdown + math.ceil(115 / 2), 30)
helmFrames.speed = helmSpeed
helmFrames.takeoffTicks, helmFrames.jumpHeight = takeoffTicks, math.max(0, helmJumpHeight)
helmFrames.fallSpeed, helmFrames.fallSourceTicks = helmFallSpeed, fallSourceTicks
helmFrames.hitStarts = {}
for offset = 0, 12, 2 do
    helmFrames.hitStarts[#helmFrames.hitStarts + 1] = touchdown + offset
end
helmFrames.bonusHitsPerRate, helmFrames.maxHits = 3.5, 14 -- 面板射速翻倍时额外刀数四舍五入。

local function motionMultiplier(points)
    return points / 10 -- 20 动作值打两倍起手面板伤害。
end

local thrustLength, thrustHalfWidth = 60, 12
local roundSlashRadius = 64
local sheatheEntrySpeed = 2 -- 仅 306 起手倍速，进入架势后按原速循环。

return {
    MOD_NAME = "Longsword M0 Probe",
    ITEM_NAME = "Hellish Slasher",
    LOG_PREFIX = "[LS_M0] ",
    COMMAND = "ls_probe",
    PROBE_EQUIP_KEY = Keyboard.KEY_F6, -- Temporary M0 test key, not a combat binding.
    DEBUG_TEXT_KEY = Keyboard.KEY_F7,
    PROBE_BLADE_KEY = Keyboard.KEY_F8, -- Temporary blade cycle alongside round-slash hit awards.
    MOUSE_CURSOR = {
        enabled = true,
        path = "gfx/ui/cursor.anm2", -- Native UI asset; its pivot already places the pointer.
        animation = "Idle", frame = 0, scale = 1,
    },
    CHARGE_INDICATOR = {
        enabled = true,
        path = "gfx/chargebar.anm2", -- Native circular charge display; no weapon entity needed.
        chargingAnimation = "Charging", chargingLastFrame = 100,
        readyAnimation = "Charged", readyFrames = 6,
        offsetX = 18, offsetY = -30, scale = 1,
    },
    -- E24: keep facing when the cursor is almost on the player (screen units).
    MOUSE_AIM = { enabled = true, minDistance = 2 },
    -- T58: native physical stick codes verified under Rep+ with the current Steam mapping.
    CONTROLLER_AIM = {
        deadzone = 0.2,
        -- Read the stick before native shooting actions merge it with face buttons.
        axes = { left = 43951, right = 43952, up = 43953, down = 43954 },
    },
    -- 战斗键只改这里；改完重启游戏。action 跟随游戏设置，key 是指定键盘键。
    -- mouse 为原生鼠标编号，仅键鼠启用：0左键、1右键、2中键、3后退侧键、4前进侧键。
    -- R10本机实测编号：上Y=6、右B=5、左X=4、下A=7；不同设备可在此修改。
    -- 例如把 RIGHT 改为 { key = Keyboard.KEY_K }，就用 K 刺挑；{} 表示不绑定。
    -- 可给下方三个独立招式键填 key，从而不必按组合键；动作逻辑无需修改。
    COMBAT_BINDINGS = {
        UP = { action = ButtonAction.ACTION_SHOOTUP },       -- 键盘↑：保留独立直斩
        MOUSE_PRIMARY = { button = 6, mouse = 0 },            -- 鼠标左键／Y：直斩进入后摇时，同次持有接蓄力
        RIGHT = { action = ButtonAction.ACTION_SHOOTRIGHT, button = 5, mouse = 1 }, -- 右键／B：长按刺挑
        LEFT = { action = ButtonAction.ACTION_SHOOTLEFT },   -- 键盘←：保留独立蓄力；手柄X默认空出
        DOWN = { action = ButtonAction.ACTION_SHOOTDOWN, button = 7, mouse = 4 },   -- 前进侧键／A：纳刀闪步
        POCKET = { pocket = true },                         -- 原版口袋使用键（默认Q），气刃／居合＋组合
        SKILL = { mouse = 3 },                              -- 后侧：延迟单用气刃／长按循环，也修饰三种组合
        SPIRIT = {},                                       -- 可选独立气刃键，如 { key = Keyboard.KEY_C }
        MODIFIER = {},                                     -- 可选纯修饰键；后侧走SKILL的组合等待
        FORESIGHT = {},                                     -- 独立见切键
        SPECIAL_SHEATHE = {},                               -- 独立特殊纳刀键
        SPIRIT_THRUST = {},                                 -- 可选独立气刃突刺键，默认口袋＋上
    },
    -- 以下是战斗时间的唯一配置；单位为原生更新tick（30 tick = 1秒）。
    -- 后续按音效节奏换算到tick再微调；全部是实验值，不是定稿。
    -- 普通姿态口袋组合等待；特殊纳刀内居合立即请求，不等此窗口。
    POCKET_COMBO_FRAMES = 3,
    MOUSE_SKILL_COMBO_FRAMES = 5, -- E30: 后侧单用等待约0.17秒，留出组合窗口；原Q窗口不变
    -- E06 experimental update ticks: 30 updates/second; timings are not final balance.
    ACTIONS = {
        baseFireRate = 2.5,    -- Tears per second at authored animation and charge speed.
        frames = {
            -- E16: 留足观察和命中时间；active是持续判定tick，不是贴图帧数。
            NORMAL = animationFrames(gameFrame(50), gameFrame(81), 76, 32),
            THRUST = clipFrames(15, 40, 66, 32),
            RISING = clipFrames(15, 36, 69, 33), -- Recovery follows source frame 35.
            -- Authored active source frames (inclusive): 35-55, 25-45 and 15-100.
            SPIRIT_I = clipFrames(35, 56, 72, 33),
            SPIRIT_II = clipFrames(25, 46, 61, 33),
            SPIRIT_III = spiritIIIFrames,
            ROUND_SLASH = clipFrames(15, 46, 80, 28), -- 109 includes the full return to the sheath.
            FORESIGHT = foresightFrames,
            IAI = iaiFrames,
            SPIRIT_THRUST = spiritThrustFrames,
            HELM_BREAKER = helmFrames,
        },
        chargeFrames = 45,     -- 标准射速 2.5 时，从实际起蓄到满蓄为 1.5 秒
        chargeRecovery = 8,    -- 未满蓄松开后的收招
        bufferFrames = 40,     -- E16: 覆盖加长后的完整招式，P2仍等待合法衔接点
        -- E07: qualification uses actual attack starts, not hits or charge holding.
        recentAttackFrames = 60, -- 最近实际攻击资格窗口
        sheatheSeatFrame = math.ceil(gameFrame(73) / sheatheEntrySpeed),
        sheatheStartup = math.ceil(75 / (2 * sheatheEntrySpeed)), -- 源帧 76 起可接居合／闪步
        sheatheTimeout = 150,   -- 特殊纳刀无操作维持时长
        stepFrames = 6,         -- E10: 闪步持续0.2秒，开始时刷新纳刀，期间暂停倒计时
    },
    STEP_DISTANCE = 60,        -- E11: 标称距离，速度=距离/stepFrames；实际位移受原生物理/碰撞影响
    -- 308 拔刀突进：源帧 21 仍在鞘，26 完全拔出。窗口 [23, 35)，距离为世界单位。
    IAI_DASH = { distance = 60, firstFrame = gameFrame(23), endFrame = gameFrame(35) },
    -- 170 起手即挡普通伤害。刺中才起跳，挥空到后摇时收回保护。
    ACTION_PROTECTION = {
        SPIRIT_THRUST = { STARTUP = true, ACTIVE = true },
        HELM_BREAKER = { STARTUP = true, ACTIVE = true, RECOVERY = true },
        FORESIGHT = { ACTIVE = true, lastFrame = foresightFrames.firstHitFrame },
        IAI = { STARTUP = true, ACTIVE = true },
    },
    -- 居合为首次挡伤后的总秒数；见切为成功见切或其反击大回旋结束后的余量。0 关闭对应护盾。
    COUNTER_SHIELD_SECONDS = { IAI = 2, FORESIGHT = 0.2, HELM_BREAKER = 0.2 },
    SPIRIT_THRUST = {
        distance = 75,         -- E13: 有效阶段突进标称距离，起手锁定四向
    },
    HELM_AIR_STEER = { radius = 40, framesToEdge = 9 }, -- 从起跳点最多移动一格，满输入到边缘用 9 tick。
    -- E15: 所有近战范围、倍率和显示参数均为可替换实验值。
    -- range从玩家中心算，目标Size计入边界；line.width是横向半宽。
    MELEE = {
        hitstop = {
            minFrames = 3, maxFrames = 4, damagePerFrame = 4, movementScale = 0.25, shake = 2,
            actions = { NORMAL = true, SPIRIT_I = true, SPIRIT_II = true, SPIRIT_III = true,
                ROUND_SLASH = true, FORESIGHT = true, IAI = true },
        },
        hitAreaScale = 1.3, -- 围绕角色放大命中区域；不影响贴图、实际移动或敌人体型。
        size = { baseRange = 260, rangeDivisor = 2.5, isaacDamage = 3.5,
            initialTearScale = 1 }, -- Used until a fresh ordinary Isaac supplies the native reference.
        damageFlags = 0,
        damageCountdown = 0,
        -- 可选 damageModifier(context, target, amount) 返回联动后的伤害；默认不修改。
        bladeMultipliers = { 1, 1, 1, 1 },
        spiritBladeMultipliers = { 1, 1.05, 1.10, 1.20 }, -- 无、白、黄、红；含气刃连段的收尾大回旋。
        profiles = {
            NORMAL = { mode = "line", range = thrustLength, width = thrustHalfWidth, multiplier = motionMultiplier(24) },
            THRUST = { mode = "line", range = thrustLength, width = thrustHalfWidth, multiplier = motionMultiplier(12) },
            RISING = { mode = "arc", range = 48, multiplier = motionMultiplier(18) },
            SPIRIT_I = { mode = "arc", range = 56, multiplier = motionMultiplier(26), spiritCombo = true },
            SPIRIT_II = { mode = "arc", range = 56, multiplier = motionMultiplier(30), spiritCombo = true },
            SPIRIT_III = { mode = "radial", range = 60, multiplier = motionMultiplier(14 + 19 + 34),
                hitCount = #spiritIIIFrames.hitStarts, spiritCombo = true },
            ROUND_SLASH = { mode = "radial", range = roundSlashRadius, multiplier = motionMultiplier(38) },
            FORESIGHT = { mode = "radial", range = roundSlashRadius, multiplier = motionMultiplier(26),
                firstHitFrame = foresightFrames.firstHitFrame },
            IAI = { mode = "radial", range = roundSlashRadius, multiplier = 0.8, lastHitFrame = iaiFrames.lastHitFrame,
                bladeMultipliers = { motionMultiplier(17), motionMultiplier(19 + 55),
                    motionMultiplier(31 + 72), motionMultiplier(39 + 86) } },
            SPIRIT_THRUST = { mode = "line", range = thrustLength, width = thrustHalfWidth, multiplier = motionMultiplier(26) },
            HELM_BREAKER = { mode = "line", range = thrustLength, width = thrustHalfWidth, landingRadius = 16, multiplier = 1,
                bladeMultipliers = { 0, motionMultiplier(10), motionMultiplier(15), motionMultiplier(25) } },
        },
        visual = {
            path = "gfx/008.010_spirit sword.anm2",
            offsetX = 0, offsetY = -12, scale = 1,
            -- 原版四向动画共用向下刀光；统一底片并整体旋转以对齐判定。
            attackAnimation = "AttackDown", spinAnimation = "SpinDown",
            rotationByFacing = { Right = -90, Down = 0, Left = 90, Up = 180 },
            attackFrames = 8, spinFrames = 14,
        },
    },
    WATCH_DEFAULT = false,
    TEXT_X = 24,
    TEXT_Y = 64,
    TEXT_STEP = 12,
    -- Bottom-right pocket HUD coordinates, in game screen units.
    BLADE_BAR = {
        path = "gfx/ui/ui_chargebar.anm2",
        -- Keep the shadow on screen at zero inset. At full inset, leave 3px beside the hilt.
        right = 4, bottom = 15, insetX = 10, insetY = 3,
        rowRise = { 0, 18, 31, 43 },
        -- After converting the native green fill to luminance, restore its brightness.
        colors = { { 1.6, 1.6, 1.6 }, { 1.6, 1.35, 0.18 }, { 1.6, 0.24, 0.24 } },
    },
    -- These are native shooting actions, so the player's current bindings apply.
    DIRECTIONS = {
        { name = "LEFT", action = ButtonAction.ACTION_SHOOTLEFT },
        { name = "RIGHT", action = ButtonAction.ACTION_SHOOTRIGHT },
        { name = "UP", action = ButtonAction.ACTION_SHOOTUP },
        { name = "DOWN", action = ButtonAction.ACTION_SHOOTDOWN },
    },
}
