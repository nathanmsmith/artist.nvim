---@meta

---@class Artist.Position
---@field row integer One-based display row.
---@field col integer One-based display column.

---@alias Artist.PositionLike Artist.Position|[integer, integer]

---@class Artist.Point: Artist.Position
---@field char string

---@class Artist.Change: Artist.Point
---@field before string

---@class Artist.GridContinuation
---@field continuation true
---@field lead integer

---@alias Artist.GridCell string|Artist.GridContinuation

---@class Artist.Timer
---@field start fun(self: Artist.Timer, timeout: integer, repeat_interval: integer, callback: function)
---@field stop fun(self: Artist.Timer)
---@field close fun(self: Artist.Timer)

---@class Artist.Options
---@field tool? string
---@field aspect_ratio? number
---@field rubber_banding? boolean
---@field first_character? string
---@field second_character? string
---@field line_character? string
---@field fill_character? string
---@field default_fill_character? string
---@field pen_character? string
---@field erase_character? string
---@field arrow_characters? (string|false)[]
---@field first_arrow? boolean
---@field second_arrow? boolean
---@field trim_line_endings? boolean
---@field flood_fill_right_boundary? integer|'window_width'|'fill_column'
---@field fill_column? integer
---@field flood_fill_incremental? boolean
---@field ellipse_left_character? string
---@field ellipse_right_character? string
---@field borderless_shapes? boolean
---@field borderless? boolean
---@field vaporize_fuzziness? integer
---@field spray_interval? number
---@field spray_radius? integer
---@field spray_characters? string[]
---@field spray_initial_character? string
---@field timer_factory? fun(): Artist.Timer
---@field text_renderer? fun(text: string, options: Artist.Options): string|string[]
---@field figlet_executable? string
---@field figlet_font? string
---@field rectangle_register? string|false
---@field mappings? boolean
---@field mouse_wheel? boolean
---@field winbar? boolean
---@field transparent_selection? boolean
---@field overwrite? boolean
---@field bufnr? integer
---@field tabstop? integer
---@field window_width? integer
---@field text? string
---@field rng? fun(minimum: integer, maximum: integer): integer

---@class Artist.GridOptions
---@field tabstop? integer

---@class Artist.PatchOptions
---@field trim_line_endings? boolean

---@class Artist.PatchSetOptions
---@field intersect? boolean

---@alias Artist.OperationKind 'continuous'|'one_point'|'two_point'|'poly_point'

---@class Artist.OperationDefinition
---@field label string
---@field kind Artist.OperationKind
---@field shifted string
---@field arrows? boolean
---@field fill? boolean
---@field geometry? string

---@class Artist.Drag
---@field operation string
---@field start Artist.Position
---@field current Artist.Position
---@field transaction Artist.Patch

---@class Artist.PreviousWindowOptions
---@field virtualedit table<integer, string>
---@field wrap table<integer, boolean>
---@field winbar table<integer, string>
---@field winhighlight table<integer, string>

---@class Artist.Session
---@field bufnr integer
---@field tool string
---@field legacy_freehand boolean
---@field options Artist.Options
---@field first_arrow boolean
---@field second_arrow boolean
---@field active_windows table<integer, true>
---@field previous Artist.PreviousWindowOptions
---@field anchor? Artist.Position
---@field keyboard_position? Artist.Position
---@field poly_points? Artist.Position[]
---@field transaction? Artist.Patch
---@field preview_transaction? Artist.Patch
---@field drag? Artist.Drag
---@field continuous_active? boolean
---@field timer? Artist.Timer|uv.uv_timer_t
---@field saved_mappings? table<string, table>
---@field mapping_definitions? table[]

return {}
