-- Copyright (c) 2026 treevar. All rights reserved.
-- Licensed under a modified MIT License <https://github.com/treevar/mc-cc/blob/main/LICENSE>

-- GCode mappings
GCode = {
    worldLimits = {
        X = {
            min = {
                overworld = -29999984,
                nether = -29999984,
                ender = -29999984
            },
            max = {
                overworld = 29999984,
                nether = 29999984,
                ender = 29999984
            },
        },
        Y = {
            min = {
                overworld = -64,
                nether = 0,
                ender = 0
            },
            max = {
                overworld = 319,
                nether = 255,
                ender = 255
            },
        },
        Z = {
            min = {
                overworld = -29999984,
                nether = -29999984,
                ender = -29999984
            },
            max = {
                overworld = 29999984,
                nether = 29999984,
                ender = 29999984
            },
        }
    },
    modal = {
        --G
        MOTION = "MOTION",
        PLANE = "PLANE",
        DISTANCE = "DISTANCE",
        SCALE = "SCALE",
        WCS = "WCS",
        --M
        PROG_FLOW = "PROG_FLOW"
    },
    plane = {
        XY = "XY",
        ZX = "ZX",
        YZ = "YZ"
    },
    coordMode = {
        ABS = "ABS",
        REL = "REL"
    },
    motionMode = {
        MOVE = "MOVE", --No cut
        LINE = "LINE", --Cut
        CIRC_CW = "CIRC_CW",
        CIRC_CCW = "CIRC_CCW",
        DRILL = "DRILL"
    },
    param = { --Params that may be used by commands, any others are ignored
        --Coords
        X = "X",
        Y = "Y",
        Z = "Z",
        --Arc
        I = "I", --X center point
        J = "J", --Y center point,
        K = "K", --Z center point,
        R = "R",
        T = "T",
        Q = "Q",
        P = "P", --Dwell time
        L = "L", 
    },
    error = {
        GRID = "Grid violation",
        SYNTAX = "Invalid syntax",
        PARAM_BAD_VAL = "Bad value for parameter",
        CMD_UNKNOWN = "Unknown command",
        FILE_NX = "Can't find file",
        FILE_OPEN = "Can't open file",
        SUBPROG_PARAM = "Subprogram call with params that are used by another command in the block",
        SUBPROG_CALL_RETURN = "Can't call subprogram and return from subprogram in same block",
    },
    haltType = {
        NONE = 0,
        MACHINE = 1,    --Called by the machine (terminates)
        STOP = 2,       --Stops reading program and terminates
        WAIT = 3        --Halts and waits for user input
    },
    wcsIdx = {
        G54 = 1,
        G55 = 2,
        G56 = 3,
        G57 = 4,
        G58 = 6,
        G59 = 6,
    }
}

GCode.allParamsStr = ""

for p, v in pairs(GCode.param) do
    GCode.allParamsStr = GCode.allParamsStr .. p
end

GCode.allCmdLettersStr = "GM"

GCode.allLettersStr = GCode.allCmdLettersStr .. GCode.allParamsStr

GCode.code = {
    G00 = {
        str = "G00",
        desc = "Rapid move", --No cutting
        optArgs = {
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true}
        },
        modal = GCode.modal.MOTION
    },
    G01 = {
        str = "G01",
        desc = "Linear interpolation",
        optArgs = {
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true}
        },
        modal = GCode.modal.MOTION
    },
    G02 = {
        str = "G02",
        desc = "Circular interpolation (CW)",
        optArgs = {
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true}
        },
        reqArgs = {{c = "R", float = true, round = true}},
        modal = GCode.modal.MOTION
    },
    G03 = {
        str = "G03",
        desc = "Circular interpolation (CCW)",
        optArgs = {
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true}
        },
        reqArgs = {{c = "R", float = true, round = true}},
        modal = GCode.modal.MOTION
    },
    G04 = { --
        str = "G04",
        desc = "Dwell sec",
        reqArgs = {{c = "P", float = true}}
    },
    G10 = {
        str = "G10",
        desc = "Set params",
        reqArgs = {{c = "L"}},
        optArgs = { 
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true},
            {c = "P"}
        }
        --No modal
    },
    G13 = {
        str = "G13",
        desc = "Circular Pocket Milling (CCW)",
        reqArgs = {{c = "K", float = true, round = true}},
        optArgs = {
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true}, 
            {c = "I", float = true, round = true}, 
            {c = "Q", float = true, round = true},
        },
        modal = GCode.modal.MOTION
    },
    G17 = {
        str = "G17",
        desc = "Select XY plane",
        modal = GCode.modal.PLANE
    },
    G18 = {
        str = "G18",
        desc = "Select ZX plane",
        modal = GCode.modal.PLANE
    },
    G19 = {
        str = "G19",
        desc = "Select YZ plane",
        modal = GCode.modal.PLANE
    },
    G28 = {
        str = "G28",
        desc = "Return to home position"
        --No modal
    },
    G50 = {
        str = "G50",
        desc = "Cancel scaling",
        modal = GCode.modal.SCALE
    },
    G51 = {
        str = "G51",
        desc = "Scale",
        optArgs = {
            {c = "X", float = true}, 
            {c = "Y", float = true}, 
            {c = "Z", float = true},
            {c = "P", float = true}, 
            {c = "I", float = true}, 
            {c = "J", float = true},
            {c = "K", float = true},
        },
        modal = GCode.modal.SCALE
    },
    G54 = {
        str = "G54",
        desc = "Work coord 1",
        modal = GCode.modal.WCS
    },
    G55 = {
        str = "G55",
        desc = "Work coord 2",
        modal = GCode.modal.WCS
    },
    G56 = {
        str = "G56",
        desc = "Work coord 3",
        modal = GCode.modal.WCS
    },
    G57 = {
        str = "G57",
        desc = "Work coord 4",
        modal = GCode.modal.WCS
    },
    G58 = {
        str = "G58",
        desc = "Work coord 5",
        modal = GCode.modal.WCS
    },
    G59 = {
        str = "G59",
        desc = "Work coord 6",
        modal = GCode.modal.WCS
    },
    G81 = {
        str = "G81",
        desc = "Drilling cycle",
        optArgs = {
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true}, 
        },
        modal = GCode.modal.MOTION
    },
    G90 = {
        str = "G90",
        desc = "Absolute coords",
        modal = GCode.modal.DISTANCE
    },
    G91 = {
        str = "G91",
        desc = "Relative coords",
        modal = GCode.modal.DISTANCE
    },
    G92 = {
        str = "G92",
        desc = "Set pos"
        --No modal
    },
    G98 = {
        str = "G98",
        desc = "Return to initial point",
        modal = GCode.modal.MOTION
    },
    G99 = {
        str = "G99",
        desc = "Return to R point",
        modal = GCode.modal.MOTION
    },
    G150 = {
        str = "G150",
        desc = "Rectangular Pocket Milling",
        reqArgs = {
            {c = "I", float = true, round = true}, 
            {c = "K", float = true, round = true}, 
        }, -- width and length
        optArgs = {
            {c = "X", float = true, round = true}, 
            {c = "Y", float = true, round = true}, 
            {c = "Z", float = true, round = true},
            {c = "Q", float = true, round = true},
        },
        modal = GCode.modal.MOTION
    },
    M00 = {
        str = "M00",
        desc = "Halt until user interrupts",
        modal = GCode.modal.PROG_FLOW
    },
    M02 = {
        str = "M02",
        desc = "Halt",
        modal = GCode.modal.PROG_FLOW
    },
    M06 = {
        str = "M06",
        desc = "Tool change",
        reqArgs = {{c = "T"}}
        --No modal
    },
    M30 = {
        str = "M30",
        desc = "Halt & rewind",
        modal = GCode.modal.PROG_FLOW
    },
    M98 = {
        str = "M98",
        desc = "Call subprogram",
        reqArgs = {"P"},
        optArgs = {"X", "Y", "Z", "I", "J", "K", "R", "T", "Q", "L"}
        --No modal
    },
    M99 = {
        str = "M99",
        desc = "Return from subprogram"
        --No modal
    },
    --Jokes
    M08 = {
        str = "M08",
        desc = "Flood coolant"
        --No modal
    },
    M09 = {
        str = "M09",
        desc = "Coolant off"
        --No modal
    }
}