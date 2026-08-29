-- Runtime event names are development hints only.  Registering a name does
-- not prove that the current game build emits it; hanime_runtime.lua records
-- the first callback that actually fires.

return {
    "PlayAnim",
    "PlayMontageAnim",
    "EventActivateAnimID",
    "EventSelectPose",
    "EventSelectPoseState",
    "EventChangeAnimState",
    "EventAnimStateChange",
    "EventChangeGroup",
    "EventStateChange",
    "EventAnimStateComplete",
    "EventStateComplete",
    "AnimNotify_StateComplete",
}
