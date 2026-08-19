# MTS localisation — string inventory

Generated 2026-08-19 by an exhaustive multi-agent sweep of all 111 Lua files (verified by pattern-audit + sampling). Line numbers are valid as of commit `e755abe`.

**754 user-visible strings** — status: {'hardcoded': 736, 'localised': 11, 'partial': 7}; visibility: {'log-only': 52, 'player': 519, 'external': 50, 'debug': 26, 'admin': 107}; categories: {'log': 76, 'chat': 111, 'gui': 234, 'external': 50, 'flying-text': 12, 'tooltip': 114, 'other': 23, 'command': 119, 'error': 4, 'prototype': 6, 'setting': 5}; hazards: {'concat': 290, 'server-side-string': 170, 'plural': 22, 'discord-mirror': 54, 'sentence-fragments': 165, 'rich-text': 120, 'symbol-only': 35, 'newlines': 41}.

Hazard glossary: `concat` = sentence assembled with `..` (needs a parameterised key); `server-side-string` = flattened to one plain string before display (blocks per-player language); `sentence-fragments` = reusable fragment composed into sentences elsewhere; `rich-text` = embeds `[color=]`/`[item=]` tags (fine in locale values/params); `discord-mirror` = also sent to Discord (needs a separate plain-English path); `plural` = hardcoded singular/plural or Lua ternary plural pick (needs `__plural_for_parameter__`); `symbol-only` = icon/symbol caption (may not need a key); `newlines` = embedded `\n` layout; `sorted-by-text` = list ordered by the display string.


## compat/compat_utils.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 92 | log | hardcoded | log-only | concat,server-side-string | compat_utils.process_pending_teleports: TELEPORT → <surface.name> | "...TELEPORT → " .. surface.name; helpers.diag then prepends "[multi-team-support:DIAG] " and appends " \| " .… |

## compat/dangoreus.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 153 | chat | hardcoded | player | plural | Cannot build non-miners on resources! |  |

## compat/mts_dimension_warp.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 63 | log | hardcoded | log-only | concat,server-side-string | mts_dimension_warp.setup_player_surface: neo-nauvis planet missing -> vanilla fallback | two static literals joined with ..; helpers.diag wraps with "[multi-team-support:DIAG] " prefix and " \| " .. … |
| 83 | log | hardcoded | log-only | concat,server-side-string | mts_dimension_warp.setup_player_surface: create_team_surface failed -> vanilla fallback | two static literals joined with ..; helpers.diag wraps with "[multi-team-support:DIAG] " prefix and " \| " .. … |

## compat/platformer.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 49 | gui | hardcoded | player | concat,server-side-string | <player.name>'s hub | player.name .. "'s hub" — English possessive concatenated onto the player name; becomes the space platform's n… |
| 64 | chat | hardcoded | player |  | [multi-team-support] Could not create personal space platform. |  |
| 104 | log | hardcoded | log-only | concat,server-side-string | platformer.process_pending_teleports: TELEPORT → <surface.name> | "...TELEPORT → " .. surface.name; helpers.diag wraps with "[multi-team-support:DIAG] " prefix and " \| " .. pl… |

## control.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 90 | log | hardcoded | log-only |  | [multi-team-support] on_init fired |  |
| 164 | log | hardcoded | log-only |  | [multi-team-support] on_configuration_changed fired |  |

## events/chat.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 34 | external | hardcoded | external | server-side-string,discord-mirror | Server | passed as the author-name argument to remote_api.emit_chat("Server", message, nil) for server-console (stdin) … |
| 51 | chat | hardcoded | player | concat,server-side-string | <prefix><author>: <message> | prefix from spectator.get_chat_prefix(author) .. author.name .. ": " .. message; printed per connected player … |
| 67 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… | [spectating]  | ternary: tag = author_swapped and "[spectating] " or ""; prepended by concat to the team-chat relay at line 72 |
| 72 | chat | hardcoded | player | concat,server-side-string | <tag><author>: <message> | tag ("[spectating] " or "") .. author.name .. ": " .. message; printed to effective-team members with {color =… |

## events/gui_clicks.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 53 | chat | hardcoded | player | concat,rich-text,server-side-string | <colored name> has joined <team tag>. | helpers.colored_name(player.name, player.chat_color) .. " has joined " .. helpers.team_tag(player.force.name) … |

## events/gui_state.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 37 | chat | hardcoded | player | concat,rich-text,server-side-string | [Admin] <colored name> set max team size to <n> | "[Admin] " .. helpers.colored_name(p.name, p.chat_color) .. " set max team size to " .. new_limit (number auto… |
| 49 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <team tag> is no longer recruiting (team size limit reached). | "[Team] " .. helpers.team_tag(fn) .. " is no longer recruiting (team size limit reached)." broadcast to all |
| 154 | chat | hardcoded | player | sentence-fragments,concat,server-side-st… | enabled / disabled | ternary picks "enabled" or "disabled" from the admin flag's new state; spliced into the [Admin] broadcast at l… |
| 156 | chat | hardcoded | player | concat,rich-text,sentence-fragments,serv… | [Admin] <colored name> <enabled\|disabled> <flag label> | "[Admin] " .. helpers.colored_name(admin_player.name, chat_color) .. " " .. state_str .. " " .. admin_gui.get_… |
| 199 | chat | hardcoded | player | rich-text,server-side-string | [color=1,0.65,0]Per-team modifiers are now allowed — team times are no longer directly comparab… |  |

## events/player_lifecycle.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 89 | chat | hardcoded | player | concat,server-side-string | Welcome <name>! | "Welcome " .. player.name .. "!"; may be extended by the Discord suffix at line 91 before helpers.broadcast |
| 91 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… |  Join our Discord for reset notifications: <url> | appended when settings.global["mts_discord_url"].value is non-empty: msg .. " Join our Discord for reset notif… |
| 106 | chat | hardcoded | player | concat,rich-text,plural,server-side-stri… | Teams looking for more players: <tag>, <tag>. | "Teams looking for more players: " .. table.concat(lfm_tags, ", ") .. "." — lfm_tags are rich-text helpers.tea… |
| 113 | chat | hardcoded | player | concat,rich-text,server-side-string | Welcome back <name> <team tag with leader>! | "Welcome back " .. player.name .. " " .. helpers.team_tag_with_leader(player.force.name) .. "!" |
| 115 | chat | hardcoded | player | concat,server-side-string | Welcome back <name>! | "Welcome back " .. player.name .. "!" (non-team-force branch) |
| 132 | chat | hardcoded | player | concat,rich-text,plural,server-side-stri… | Teams looking for more players: <tag>, <tag>. | duplicate of line 106 block, fired for a returning player who lands in the pen; same table.concat assembly |

## events/player_surface.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 19 | log | hardcoded | debug |  | on_player_changed_surface (before handlers) | helpers.diag(msg, player) — the diag pipeline appends player context; only emits under the debug flag |
| 46 | flying-text | hardcoded | player | concat,rich-text | Welcome <colored name>! | "Welcome " .. helpers.colored_name(player.name, player.chat_color) .. "!" passed to pop_text.spawn_confirm |
| 52 | flying-text | hardcoded | player | concat,rich-text | <colored name> joined! | helpers.colored_name(player.name, player.chat_color) .. " joined!" passed to pop_text.team_join for each conne… |
| 57 | log | hardcoded | debug |  | on_player_changed_surface (after handlers) | helpers.diag |
| 64 | log | hardcoded | debug | concat | on_player_controller_changed (before handlers, old_ctrl=<n>) | "...old_ctrl=" .. tostring(event.old_type) .. ")" passed to helpers.diag |
| 85 | log | hardcoded | debug | concat | god_pre_remote: restoring god to <surface> | "god_pre_remote: restoring god to " .. saved.surface_name passed to helpers.diag |
| 94 | log | hardcoded | debug |  | on_player_controller_changed (after handlers) | helpers.diag |

## events/research.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 35 | external | hardcoded | external | server-side-string,discord-mirror,concat | %s researched `%s` | string.format(fmt, team, research.name) — team is storage.team_names display name or force name; research.name… |

## events/ticks.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 253 | chat | hardcoded | player | concat,server-side-string | Join our Discord for reset notifications and to vote on the next game: <url> | literal .. settings.global["mts_discord_url"].value; broadcast every 6 hours via helpers.broadcast when the UR… |

## gui/admin.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 45 | gui | hardcoded | admin |  | Admin |  |
| 51 | tooltip | hardcoded | admin |  | Close panel |  |
| 59 | gui | hardcoded | admin |  | Feature Flags |  |
| 91 | gui | hardcoded | admin |  | Max team size |  |
| 92 | tooltip | hardcoded | admin |  | Maximum number of players allowed in a team via buddy join. Only enforced at join time. |  |
| 105 | tooltip | hardcoded | admin |  | Maximum number of players allowed in a team via buddy join. |  |
| 114 | gui | hardcoded | admin |  | Team Modifiers (non-competitive) |  |
| 119 | gui | hardcoded | admin |  | Per-team settings. Every change is announced to all players. |  |
| 145 | tooltip | hardcoded | admin | concat,sentence-fragments | <def.label> for this team. <def.tooltip> | def.label .. " for this team. " .. def.tooltip — glues two data strings from scripts/team_modifiers.MODIFIERS … |
| 152 | gui | hardcoded | admin | concat,rich-text,server-side-string | <team tag with leader> <badge> | helpers.team_tag_with_leader(force_name) .. (badge and (" " .. badge) or "") — team rich-text tag plus team_mo… |
| 155 | tooltip | hardcoded | admin |  | This team has played with modifiers and is marked non-competitive. The mark clears only when th… |  |
| 162 | gui | hardcoded | admin |  |   (no teams yet) |  |
| 169 | gui | hardcoded | admin |  | Starter Items |  |
| 182 | gui | hardcoded | admin |  | Copy from my inventory |  |
| 183 | tooltip | hardcoded | admin |  | Replace the starter items list with everything in your character inventories. |  |
| 186 | gui | hardcoded | admin |  | Items given when returning to pen: |  |
| 199 | gui | hardcoded | admin |  | <item.name> | caption = item.name — raw internal prototype name shown instead of localised_name |
| 203 | gui | hardcoded | admin | concat | <item.name> [+grid] | item.name .. " [+grid]" |
| 204 | tooltip | hardcoded | admin | concat | Equipment: <list> | "Equipment: " .. table.concat(equipment internal names, ", ") |
| 206 | gui | hardcoded | admin | concat | x<count> | "x" .. item.count |
| 213 | tooltip | hardcoded | admin | concat | Remove <item.name> | "Remove " .. item.name (internal name) |
| 217 | gui | hardcoded | admin |  |   (using default items) |  |
| 227 | gui | hardcoded | admin |  | Add: |  |
| 232 | tooltip | hardcoded | admin |  | Select an item to add |  |
| 237 | gui | hardcoded | admin |  | 1 | numeric default text of the count textfield; locale-neutral |
| 241 | tooltip | hardcoded | admin |  | Count |  |
| 247 | gui | hardcoded | admin | symbol-only | + |  |
| 249 | tooltip | hardcoded | admin |  | Add this item to the starter list |  |
| 253 | gui | hardcoded | admin |  | Run Info |  |
| 264 | gui | hardcoded | admin |  | Description shown on the landing-pen panel: |  |
| 267 | gui | hardcoded | admin |  | Players read this when they land. Edit and Save any time. |  |
| 281 | gui | hardcoded | admin |  | Save description |  |
| 283 | tooltip | hardcoded | admin |  | Update the landing-pen info panel with this text. |  |
| 318 | chat | hardcoded | admin |  | Landing-pen info panel updated. |  |
| 439 | log | hardcoded | log-only | concat | [multi-team-support] admin flag changed by <player>: <key> = <state> | "[multi-team-support] admin flag changed by " .. player.name .. ": " .. key .. " = " .. tostring(el.state) |
| 453 | log | hardcoded | log-only | concat | [multi-team-support] buddy_team_limit changed by <player>: <limit> | "[multi-team-support] buddy_team_limit changed by " .. player.name .. ": " .. tostring(new_limit) |
| 480 | tooltip | hardcoded | admin |  | Open Admin panel |  |

## gui/awards.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 27 | gui | hardcoded | player | concat | Research | CAT_LABELS value; used as tab-button caption, prefixed "> " when selected (line 424) |
| 28 | gui | hardcoded | player | concat | Science | CAT_LABELS value; used as tab-button caption, prefixed "> " when selected (line 424) |
| 29 | gui | hardcoded | player | concat | Resources | CAT_LABELS value; used as tab-button caption, prefixed "> " when selected (line 424) |
| 84 | gui | hardcoded | player | sentence-fragments | First | milestone_prefix() return; rendered as a fragment before the item icon/name in leaderboard rows |
| 86 | gui | hardcoded | player | sentence-fragments | %d × | string.format("%d ×", threshold); rendered as a fragment before the item icon/name |
| 165 | gui | hardcoded | player |  | 1st | PLACE_LABELS[1]; English ordinal suffix |
| 165 | gui | hardcoded | player |  | 2nd | PLACE_LABELS[2]; English ordinal suffix |
| 165 | gui | hardcoded | player |  | 3rd | PLACE_LABELS[3]; English ordinal suffix |
| 223 | gui | hardcoded | player | concat | No achievements match "<query>". | "No achievements match \"" .. query .. "\"." — user search text interpolated mid-sentence |
| 228 | gui | hardcoded | player |  | Clear search |  |
| 232 | gui | hardcoded | player |  | (no records yet) |  |
| 246 | gui | hardcoded | player |  | Achievement |  |
| 272 | tooltip | localised | player |  | <prototype localised_name / helpers.tech_label(proto)> | tooltip = loc_name from resolve_row_proto: proto.localised_name (item/fluid) or helpers.tech_label(proto) (tec… |
| 281 | gui | hardcoded | player | server-side-string | <row.display or row.name> | fallback cell when no prototype exists: external-milestone noun registered by another mod via storage.mileston… |
| 294 | gui | hardcoded | player | symbol-only | — | fallback when a place has no elapsed value |
| 297 | gui | hardcoded | player | concat,rich-text,server-side-string | <team tag with leader>  <time> | helpers.team_tag_with_leader(e.team) .. "  " .. helpers.format_elapsed(value) (or "—") — two-space separator |
| 303 | gui | hardcoded | player | symbol-only | — | empty leaderboard place |
| 348 | gui | hardcoded | player | plural | %d / %d match | string.format("%d / %d match", #visible_rows, #all_rows) |
| 392 | gui | hardcoded | player |  | Team Awards |  |
| 405 | tooltip | hardcoded | player |  | Close |  |
| 424 | gui | hardcoded | player | concat,symbol-only | >  | sel and ("> " .. CAT_LABELS[cat]) or CAT_LABELS[cat] — selected-tab marker prefix |
| 431 | gui | hardcoded | player |  | Rank by: |  |
| 432 | tooltip | hardcoded | player |  | Which clock ranks the finishers. Server time is the official awards basis; Online time is faire… |  |
| 438 | gui | hardcoded | player |  | Server | switch left_label_caption |
| 439 | gui | hardcoded | player |  | Online | switch right_label_caption |
| 440 | tooltip | hardcoded | player |  | Elapsed since each team started, the official awards basis. |  |
| 441 | tooltip | hardcoded | player |  | How long each team was actually online. |  |
| 456 | gui | hardcoded | player | plural | %d / %d match | string.format("%d / %d match", #visible_rows, #all_rows); empty string when no query |
| 462 | gui | hardcoded | player |  | Search: |  |
| 467 | tooltip | hardcoded | player |  | Filter rows whose internal name contains this text. Case-insensitive (e.g. "miner", "science"). |  |
| 476 | tooltip | hardcoded | player |  | Clear search |  |
| 595 | tooltip | hardcoded | player |  | Team Awards |  |

## gui/buddy_requests.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 45 | gui | hardcoded | player |  | Buddy Request |  |
| 47 | gui | hardcoded | player | concat,server-side-string | <requester.name> wants to join your team. | requester.name .. " wants to join your team." |
| 57 | gui | hardcoded | player |  | Accept |  |
| 63 | gui | hardcoded | player |  | Reject |  |
| 108 | chat | hardcoded | player | concat,rich-text,server-side-string | <team tag> is full. | helpers.team_tag(force_name) .. " is full." |
| 118 | chat | hardcoded | player | concat,rich-text,server-side-string | You requested to join <team tag>. Waiting for a member to approve. | "You requested to join " .. helpers.team_tag_with_leader(force_name) .. ". Waiting for a member to approve." |
| 120 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <requester> wants to join <team tag>. | "[Team] " .. helpers.colored_name(requester) .. " wants to join " .. team_tag .. "." via helpers.broadcast to … |
| 158 | chat | hardcoded | player | concat,rich-text,server-side-string | Your team is full — cannot accept <requester>.<force tag> | "Your team is full — cannot accept " .. helpers.colored_name(requester) .. "." .. helpers.force_tag(force_name… |
| 161 | chat | hardcoded | player | concat,rich-text,server-side-string | <team tag> is now full.<force tag> | helpers.team_tag(force_name) .. " is now full." .. ft (helpers.force_tag) |
| 178 | chat | hardcoded | player | concat,rich-text,server-side-string | Your inventory was cleared because you previously left this team.<force tag> | literal .. helpers.force_tag(force_name) |
| 188 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <member> accepted <requester> into <team tag>. | "[Team] " .. member_tag .. " accepted " .. requester_tag .. " into " .. team_tag .. "." via helpers.broadcast |
| 210 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <team tag> is no longer recruiting (team is now full). | "[Team] " .. helpers.team_tag(force_name) .. " is no longer recruiting (team is now full)." via helpers.broadc… |
| 257 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <requester> has joined <team tag>. | "[Team] " .. requester_tag .. " has joined " .. team_tag .. "." via helpers.broadcast |
| 260 | chat | hardcoded | player | concat,rich-text,server-side-string | <requester> has joined your team.<force tag> | helpers.colored_name(requester) .. " has joined your team." .. ft |
| 263 | chat | hardcoded | player | concat,rich-text,server-side-string | You joined <team tag>.<force tag> | "You joined " .. team_tag .. "." .. ft |
| 275 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <requester> cancelled their request to join <team tag>. | "[Team] " .. requester_tag .. " cancelled their request to join " .. team_tag .. "." via helpers.broadcast |
| 279 | chat | hardcoded | player |  | You cancelled your join request. |  |
| 305 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <member> declined <requester>'s request to join <team tag>. | "[Team] " .. member_tag .. " declined " .. requester_tag .. "'s request to join " .. team_tag .. "." — English… |
| 309 | chat | hardcoded | player | concat,rich-text,server-side-string | <member> declined your buddy request. | member_tag .. " declined your buddy request." |

## gui/chat_switch.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 56 | gui | hardcoded | player |  | GLOBAL |  |
| 57 | gui | hardcoded | player |  | TEAM |  |
| 66 | tooltip | hardcoded | player | sentence-fragments | you | moves = chat_channel.is_individual() and "you" or "your whole team"; spliced into both segment tooltips |
| 66 | tooltip | hardcoded | player | sentence-fragments | your whole team | moves fragment; spliced into both segment tooltips |
| 67 | tooltip | hardcoded | player | sentence-fragments | your messages | whose = is_individual and "your messages" or "your team's messages"; spliced into the GLOBAL segment tooltip |
| 68 | tooltip | hardcoded | player | sentence-fragments | your team's messages | whose fragment; spliced into the GLOBAL segment tooltip |
| 75 | gui | hardcoded | player |  | TEAM* | swapped and "TEAM*" or "TEAM" — asterisk flags spectator visibility of team chat |
| 77 | tooltip | hardcoded | player | concat,sentence-fragments,newlines,serve… | Chat is GLOBAL — everyone on the server sees <whose>. | "Chat is GLOBAL — everyone on the server sees " .. whose .. "." plus conditional appended sentence (line 78) |
| 78 | tooltip | hardcoded | player | concat,sentence-fragments,newlines | \nClick to switch <moves> to global chat. | appended only when the team channel is active: "\nClick to switch " .. moves .. " to global chat." |
| 79 | tooltip | hardcoded | player | concat,sentence-fragments,newlines,serve… | Chat is TEAM-ONLY — messages stay inside your team. Start a message with ! to shout globally. | two adjacent literals concatenated, then conditional fragments appended (lines 81-83) |
| 81 | tooltip | hardcoded | player | concat,sentence-fragments,newlines | \nClick to switch <moves> to team-only chat. | appended only when global channel is active: "\nClick to switch " .. moves .. " to team-only chat." |
| 82 | tooltip | hardcoded | player | newlines,sentence-fragments | \n* While spectating, other spectators can also see your team messages. | appended only when force-swapped into spectate (two adjacent literals) |

## gui/confirm.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 51 | gui | hardcoded | player |  | Confirm | fallback title when opts.title is nil; callers pass plain-string titles |
| 56 | gui | hardcoded | player | newlines | Are you sure? | fallback body when opts.message is nil; caller messages are plain strings and may embed \n (single_line = fals… |
| 74 | gui | hardcoded | player |  | Cancel | fallback when opts.cancel_text is nil |
| 90 | gui | hardcoded | player |  | Confirm | fallback when opts.confirm_text is nil |

## gui/follow_cam_frame.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 54 | gui | hardcoded | player | concat,sentence-fragments,server-side-st… | Spectating <team display name> | "Spectating " .. (watched and helpers.display_name(watched) or "another team") |
| 55 | gui | hardcoded | player | sentence-fragments | another team | fallback fragment inside the "Spectating ..." caption |
| 99 | gui | hardcoded | player |  | Follow Cam |  |
| 105 | tooltip | hardcoded | player |  | Restore size | state.maximized and "Restore size" or "Maximize (Esc to restore)" |
| 105 | tooltip | hardcoded | player |  | Maximize (Esc to restore) | shown when not maximized |
| 112 | tooltip | hardcoded | player |  | Close Follow Cam |  |
| 168 | gui | hardcoded | player | concat |   <team display name> | "  " .. helpers.display_name(real_fn) — two-space layout indent glued to the team name |
| 183 | tooltip | hardcoded | player |  | Expand to full spectator view (Esc to return here) |  |
| 191 | gui | hardcoded | player |  | Body | phys and "Body" or "View"; fixed 46px button width may clip translations |
| 191 | gui | hardcoded | player |  | View | shown in live-view mode; fixed 46px button width may clip translations |
| 193 | tooltip | hardcoded | player |  | Tracking the player's physical body. Click to track their live view (where they're looking) ins… |  |
| 194 | tooltip | hardcoded | player |  | Tracking the player's live view (where they're looking). Click to track their physical body ins… |  |
| 203 | gui | hardcoded | player | symbol-only | − | U+2212 minus zoom-out button |
| 206 | tooltip | hardcoded | player |  | Zoom out |  |
| 215 | gui | hardcoded | player | symbol-only | + | zoom-in button |
| 218 | tooltip | hardcoded | player |  | Zoom in |  |
| 228 | tooltip | hardcoded | player |  | Remove from Follow Cam |  |

## gui/friendship.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 34 | gui | hardcoded | player | sentence-fragments | friends | returned as label_text from get_state; rendered as checkbox label by surfaces_gui (outside this file) |
| 34 | tooltip | hardcoded | player | concat,server-side-string | Break friendship with <owner> | "Break friendship with " .. owner (team owner/leader name) |
| 36 | gui | hardcoded | player | sentence-fragments | request pending | returned label_text (also line 38); rendered by surfaces_gui |
| 36 | tooltip | hardcoded | player | concat,server-side-string | Withdraw friend request to <owner> | "Withdraw friend request to " .. owner |
| 38 | tooltip | hardcoded | player | concat,server-side-string | Accept friend request from <owner> | "Accept friend request from " .. owner |
| 40 | gui | hardcoded | player | sentence-fragments | request friend | returned label_text; rendered by surfaces_gui |
| 40 | tooltip | hardcoded | player | concat,server-side-string | Send friend request to <owner> | "Send friend request to " .. owner |
| 106 | chat | hardcoded | player | concat,rich-text,server-side-string | <team A> and <team B> are now [color=0,1,0]friends[/color] | viewer_tag .. " and " .. target_tag .. " are now [color=0,1,0]friends[/color]" via helpers.broadcast |
| 109 | chat | hardcoded | player | concat,rich-text,server-side-string | <team A> wants to friend <team B> [color=1,0.8,0](pending)[/color] | viewer_tag .. " wants to friend " .. target_tag .. " [color=1,0.8,0](pending)[/color]" via helpers.broadcast |
| 118 | chat | hardcoded | player | concat,rich-text,server-side-string | <team A> and <team B> are no longer friends | viewer_tag .. " and " .. target_tag .. " are no longer friends" via helpers.broadcast |
| 120 | chat | hardcoded | player | concat,rich-text,server-side-string | <team A> withdrew friend request to <team B> | viewer_tag .. " withdrew friend request to " .. target_tag via helpers.broadcast |
| 160 | chat | hardcoded | player |  | [Admin] All friendships have been dissolved. |  |

## gui/hud_clock.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 50 | gui | hardcoded | player | rich-text | [img=utility/clock] not started |  |
| 51 | tooltip | hardcoded | player |  | The clock starts when the team leader clicks Start Playing. |  |
| 57 | tooltip | hardcoded | player |  | Time since the team started playing — the official time for records and awards. | two adjacent literals; online line appended when clocks diverge (line 61) |
| 61 | tooltip | hardcoded | player | concat,newlines,server-side-string | \nOnline (at least one member connected): <duration> | tooltip .. "\nOnline (at least one member connected): " .. helpers.fmt_duration(online) |
| 64 | gui | hardcoded | player | concat,rich-text,server-side-string | [img=utility/clock] <duration> | "[img=utility/clock] " .. helpers.fmt_duration(elapsed) — HUD chip caption, rewritten every second; also reuse… |
| 169 | chat | hardcoded | player |  | Spectator chat is always global. |  |

## gui/landing_pen.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 62 | log | hardcoded | debug | concat | landing_pen.process_pending_teleports: TELEPORT → <surface> | "landing_pen.process_pending_teleports: TELEPORT → " .. tp.surface.name passed to helpers.diag(msg, player) |
| 129 | log | hardcoded | debug | concat | landing_pen.return_to_pen: TELEPORT → <surface> | "landing_pen.return_to_pen: TELEPORT → " .. surface.name passed to helpers.diag(msg, player) |

## gui/landing_pen_terrain.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 63 | other | hardcoded | player | server-side-string | MULTI-TEAM SUPPORT | rendering.draw_text ground text on the landing-pen surface — one world-anchored render shared by all players |
| 69 | other | hardcoded | player | server-side-string | Spawn when ready | rendering.draw_text ground text on the landing-pen surface — one world-anchored render shared by all players |

## gui/lfm_hint.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 38 | gui | hardcoded | player | rich-text | [img=utility/custom_tag_icon]  Team Settings — Recruiting |  |
| 53 | tooltip | hardcoded | player |  | Close |  |
| 60 | gui | hardcoded | player | rich-text,newlines | [img=utility/warning_icon]  Your team isn't recruiting yet!\nNew players in the landing pen can… | assembled from four string literals with '..' (no runtime data; fully static at runtime, spans lines 60-63) |

## gui/pen_gui.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 44 | gui | hardcoded | player |  | ─────  OR  join a team that's recruiting  ───── |  |
| 54 | gui | hardcoded | player | concat | (max {limit} per team) | "(max " .. limit .. " per team)" — limit is admin_gui.buddy_team_limit() number |
| 70 | gui | hardcoded | player | concat,sentence-fragments | (leader: {player name}[ — offline]) | "(leader: " .. leader.name .. (connected and "" or " — offline") .. ")" — player name interpolated, ' — offlin… |
| 87 | gui | hardcoded | player |  | Pending... |  |
| 94 | gui | hardcoded | player |  | Cancel request |  |
| 96 | tooltip | hardcoded | player | concat | Withdraw your request to join {team display name} | "Withdraw your request to join " .. helpers.display_name(force_name) |
| 101 | gui | hardcoded | player | concat | Full ({member_count}/{limit}) | "Full (" .. member_count .. "/" .. limit .. ")" — two numbers interpolated |
| 107 | gui | hardcoded | player |  | No members online |  |
| 114 | gui | hardcoded | player |  | Request to join | disabled-button variant shown while the player already has a pending request elsewhere |
| 116 | tooltip | hardcoded | player |  | Cancel your pending request first to join a different team. |  |
| 123 | gui | hardcoded | player |  | Request to join |  |
| 126 | tooltip | hardcoded | player | concat | Ask {team display name} to let you join | "Ask " .. helpers.display_name(force_name) .. " to let you join" — team name embedded mid-sentence |
| 159 | gui | hardcoded | player |  | Landing Pen | passed as plain string to helpers.add_title_bar |
| 168 | gui | hardcoded | player |  | Start a new team |  |
| 172 | tooltip | hardcoded | player |  | Cancel your pending join request first to start a new team. | one of three tooltip variants picked with and/or chain (this one when has_pending) |
| 174 | tooltip | hardcoded | player |  | All team slots are in use — request to join a recruiting team below. | one of three tooltip variants picked with and/or chain (this one when no slots available) |
| 175 | tooltip | hardcoded | player |  | Claim a new team slot and spawn into the game. | one of three tooltip variants picked with and/or chain (default case) |
| 185 | gui | hardcoded | player |  | We've reached the maximum number of teams. Request to join a team that's recruiting below, or w… | two literals joined with '..' (fully static at runtime, lines 185-186) |

## gui/pen_info_panel.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 31 | other | hardcoded | player | server-side-string | An admin can describe this run from the Admin panel (Run Info tab). | default for storage.pen_info_text; written to display_panel_text on an in-world display-panel entity (also sho… |

## gui/research.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 30 | gui | hardcoded | player | concat | Research: You vs {team display name} | diff_display and ("Research: You vs " .. diff_display) — title-bar caption in diff mode |
| 30 | gui | hardcoded | player |  | Research | fallback title-bar caption when no diff target |
| 37 | tooltip | hardcoded | player |  | Close |  |
| 172 | tooltip | hardcoded | player |  | Research Comparison | nav top-bar button tooltip; the spec (incl. tooltip string) is also persisted into storage.nav_button_order by… |

## gui/research_diff.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 33 | tooltip | partial | player | concat,newlines,sentence-fragments | \nResearched: (before tracking began) | LocalisedString table {"", localised tech label, hardcoded English suffix} |
| 35 | tooltip | partial | player | concat,newlines,sentence-fragments | \nResearched: tick {tick} | LocalisedString table {"", localised tech label, "\nResearched: tick " .. entry.tick} — raw tick number concat… |
| 39 | tooltip | partial | player | concat,newlines,sentence-fragments | \nResearched: {duration} after spawn | LocalisedString table {"", localised tech label, "\nResearched: " .. helpers.fmt_duration(elapsed) .. " after … |
| 62 | tooltip | hardcoded | player | sentence-fragments | Currently researching | picked when queue position == 1; embedded into the line-63 LocalisedString tooltip via "\n" .. status |
| 62 | tooltip | hardcoded | player | concat,sentence-fragments | Queued at position {position} | "Queued at position " .. position (number); embedded into the line-63 LocalisedString tooltip via "\n" .. stat… |
| 63 | tooltip | partial | player | concat,newlines,sentence-fragments | \nProgress: {pct}% | whole tooltip is {"", localised tech label, "\n" .. status .. (pct > 0 and ("\nProgress: " .. pct .. "%") or "… |
| 122 | gui | hardcoded | player | concat | Team '{internal force name}' not found. | "Team '" .. target_force_name .. "' not found." — internal force name (e.g. team-1) interpolated |
| 133 | gui | hardcoded | player |  | < Back |  |
| 145 | gui | hardcoded | player | concat | You started {duration} earlier than {team display name} | "You started " .. fmt_duration(diff_ticks) .. " earlier than " .. target_owner — duration and name interpolate… |
| 147 | gui | hardcoded | player | concat | {team display name} started {duration} earlier than you | target_owner .. " started " .. fmt_duration(diff_ticks) .. " earlier than you" |
| 149 | gui | hardcoded | player |  | You both started at the same time | one of three context variants picked by clock comparison (lines 144-150) |
| 223 | gui | hardcoded | player |  | (none) |  |
| 234 | gui | hardcoded | player | concat,sentence-fragments | You both have researched | title fragment passed to diff_section, which renders title .. "  (" .. #list .. ")" at line 217 |
| 235 | gui | hardcoded | player | concat,sentence-fragments | {team display name} has, you don't | target_owner .. " has, you don't"; then diff_section appends "  (" .. #list .. ")" at line 217 |
| 236 | gui | hardcoded | player | concat,sentence-fragments | You have, {team display name} doesn't | "You have, " .. target_owner .. " doesn't"; then diff_section appends "  (" .. #list .. ")" at line 217 |
| 260 | gui | hardcoded | player |  | Infinite tech level differences |  |
| 273 | gui | hardcoded | player |  | Technology | table-header helper hd(txt) |
| 273 | gui | hardcoded | player |  | You | table-header helper hd(txt); third column header is the team display name (not a literal) |
| 276 | gui | hardcoded | player | concat | Lv {level} | "Lv " .. d.v_lvl — level number concatenated (viewer column) |
| 277 | gui | hardcoded | player | concat | Lv {level} | "Lv " .. d.t_lvl — level number concatenated (target column) |

## gui/research_overview.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 45 | gui | hardcoded | player | sentence-fragments | not yet spawned | returned by fmt_play_time when clock_tick is nil; used directly as a header label caption |
| 47 | gui | hardcoded | player | concat,sentence-fragments | {duration} playing | research_diff.fmt_duration(game.tick - clock_tick) .. " playing" — tick-to-time formatting plus suffix word |
| 48 | gui | hardcoded | player | concat,sentence-fragments |  ({duration} online) | caption .. " (" .. fmt_duration(online_ticks) .. " online)" — appended to the line-47 string only when the tea… |
| 116 | gui | hardcoded | player |  | No players found. |  |
| 144 | gui | hardcoded | player | symbol-only | ● | written as "\xE2\x97\x8F"; online-status bullet colored via font_color |
| 152 | gui | hardcoded | player | sentence-fragments |  (offline) | separate label appended after the team-owner name label when the team is offline |
| 157 | gui | hardcoded | player | concat |   [{count}] | "  [" .. #techs .. "]" — researched-tech count concatenated |
| 167 | tooltip | hardcoded | player | newlines | Server time since this team started (records/awards use this).\nIn parentheses: time at least o… | two literals joined with '..' (fully static at runtime, lines 167-168) |
| 178 | tooltip | hardcoded | player | concat | Compare: you vs {team display name} | "Compare: you vs " .. info.owner |
| 187 | gui | hardcoded | player | symbol-only | ▲▲ | written as "\xE2\x96\xB2\xE2\x96\xB2"; shown when section is expanded |
| 187 | gui | hardcoded | player | symbol-only | ▼▼ | written as "\xE2\x96\xBC\xE2\x96\xBC"; shown when section is collapsed |
| 189 | tooltip | hardcoded | player |  | Collapse | picked when expanded (expanded and "Collapse" or ...) |
| 189 | tooltip | hardcoded | player | concat,plural | Expand all {count} technologies | "Expand all " .. #techs .. " technologies" — count interpolated; picked when collapsed |
| 201 | gui | hardcoded | player |  | (no research yet) |  |

## gui/return_button.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 56 | gui | hardcoded | player |  | Exit remote view |  |
| 58 | tooltip | hardcoded | player |  | Return remote view to your own base |  |
| 75 | log | hardcoded | debug | concat,server-side-string | return_button: REMOTE → {surface name} | "return_button: REMOTE → " .. phys_surface.name, passed to helpers.diag(msg, player) — diagnostic channel |

## gui/start_playing_gui.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 26 | gui | hardcoded | player |  | Ready to Start? | passed as plain string to helpers.add_title_bar |
| 38 | gui | hardcoded | player | concat,rich-text,newlines | {team tag}'s clock has not started yet.\n\nUntil you click "Start Playing" you can:\n  [img=uti… | helpers.team_tag(player.force.name) .. "'s clock has not started yet..." — team tag prepended with English pos… |
| 53 | gui | hardcoded | player | rich-text,newlines | [color=0.6,1,0.6]When your team is ready, click the button below.\nYour clock will start immedi… |  |
| 60 | gui | hardcoded | player |  | ▶  Start Playing |  |
| 62 | tooltip | hardcoded | player |  | Start your team's clock and begin playing. This cannot be undone. |  |
| 69 | gui | hardcoded | player | rich-text,newlines | [color=1,0.85,0.2][img=utility/warning_icon]  Your clock is paused.\nWaiting for your team lead… |  |

## gui/stats.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 37 | tooltip | hardcoded | player |  | Production Stats |  |

## gui/stats/columns.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 34 | gui | hardcoded | player | sentence-fragments | Ores |  |
| 35 | gui | hardcoded | player | sentence-fragments | Plates |  |
| 36 | gui | hardcoded | player | sentence-fragments | Intermediates |  |
| 37 | gui | hardcoded | player | sentence-fragments | Science |  |
| 38 | gui | hardcoded | player | sentence-fragments | Fluids |  |
| 39 | gui | hardcoded | player | sentence-fragments | Custom |  |

## gui/stats/counts.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 16 | gui | hardcoded | player | sentence-fragments | 1m |  |
| 17 | gui | hardcoded | player | sentence-fragments | 10m |  |
| 18 | gui | hardcoded | player | sentence-fragments | 1h |  |
| 19 | gui | hardcoded | player | sentence-fragments | 10h |  |
| 20 | gui | hardcoded | player | sentence-fragments | All |  |
| 25 | gui | hardcoded | player |  | %.1fM | string.format("%.1fM", n / 1000000) — decimal point and 'M' suffix hardcoded; result becomes stats-cell captio… |
| 26 | gui | hardcoded | player |  | %.1fk | string.format("%.1fk", n / 1000) — decimal point and 'k' suffix hardcoded |

## gui/stats/grid.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 30 | tooltip | hardcoded | player | concat,rich-text,newlines,server-side-st… | [item=<name>,quality=<quality>] <count> | "[item=" .. item_name .. ",quality=" .. qname .. "] " .. counts.fmt(v); one line per quality, joined with tabl… |
| 84 | tooltip | partial | player | concat,rich-text,newlines | Click to change this column | LocalisedString {"", "[font=default-large-bold]" .. tag .. col.name .. "]  ", proto.localised_name or col.name… |
| 90 | tooltip | hardcoded | player |  | Click to add a fluid to this column |  |
| 91 | tooltip | hardcoded | player |  | Click to add an item to this column |  |
| 105 | gui | hardcoded | player |  | sort → |  |
| 111 | gui | hardcoded | player | symbol-only | ▼ / ▲ / · | one of three literals picked in Lua by sort state (active desc / active asc / inactive) |
| 118 | tooltip | hardcoded | player |  | Sorted high→low (click for low→high) | picked in Lua by sort state (ternary with lines 119-120) |
| 119 | tooltip | hardcoded | player |  | Sorted low→high (click to clear sort) | picked in Lua by sort state |
| 120 | tooltip | hardcoded | player |  | Sort by this column (high→low) | picked in Lua by sort state |
| 158 | gui | hardcoded | player | concat | #<slot> | "#" .. entry.slot |
| 159 | tooltip | hardcoded | player | concat,server-side-string | Team slot <slot> (<force.name>) | "Team slot " .. entry.slot .. " (" .. entry.force.name .. ")" |
| 175 | gui | hardcoded | player | concat,sentence-fragments,server-side-st… |  (offline · <ago>) | " (offline · " .. teams_data.fmt_ago(act.ago_ticks) .. ")" — embeds the English output of fmt_ago ("5m ago", "… |
| 176 | gui | hardcoded | player | sentence-fragments |  (offline) | fallback when the team has no activity record; appended after the team-name label |

## gui/stats/panel.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 97 | gui | hardcoded | player |  | Production Stats |  |
| 104 | tooltip | hardcoded | player |  | Close |  |
| 115 | gui | hardcoded | player | concat,sentence-fragments | > <category label> | sel and ("> " .. CAT_LABELS[cat]) or CAT_LABELS[cat] — selected-state prefix concatenated onto the label fragm… |
| 129 | gui | hardcoded | player | concat,sentence-fragments | > <period label> | sel and ("> " .. tp.label) or tp.label — same selected-prefix pattern as category tabs |
| 148 | gui | hardcoded | player | concat | Merged | msel and "> Merged" or "Merged" — selected-prefix variant chosen in Lua |
| 150 | tooltip | hardcoded | player |  | Sum across all qualities |  |
| 161 | gui | hardcoded | player | concat,rich-text,symbol-only | [img=quality/<name>] | "[img=quality/" .. qname .. "]" — quality prototype name interpolated into a rich-text image tag |
| 162 | tooltip | localised | player |  | <quality localised_name> | qproto and qproto.localised_name or qname — prototype LocalisedString with raw-name string fallback if the pro… |
| 188 | gui | hardcoded | player |  | (no players yet) |  |

## gui/team_card.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 30 | tooltip | hardcoded | player | concat,plural,server-side-string | <force.name> — <count> player/players | force.name .. " — " .. count .. (count == 1 and " player" or " players") — plural picked in Lua |
| 42 | gui | hardcoded | player | concat | #<slot> | "#" .. slot |
| 43 | tooltip | hardcoded | player | concat,server-side-string | Team slot <slot> (<force.name>) | "Team slot " .. slot .. " (" .. force.name .. ")" — same pattern as gui/stats/grid.lua:159 |
| 54 | gui | hardcoded | player | concat,sentence-fragments |  · <ago_text> | " · " .. activity.ago_text — ago_text is "active" or fmt_ago() English output from teams_data.lua; same captio… |
| 97 | gui | hardcoded | player | symbol-only | ★ | "\xE2\x98\x85" leader star, or "" for non-leaders, picked in Lua |
| 114 | tooltip | hardcoded | player | concat | Stop following <player> | "Stop following " .. member.name |
| 115 | tooltip | hardcoded | player | concat | Follow <player> in a mini-camera (does not move your character) | "Follow " .. member.name .. " in a mini-camera (does not move your character)" — player name mid-sentence |
| 122 | gui | hardcoded | player | symbol-only |   ● |  |
| 126 | gui | hardcoded | player | symbol-only |   ○ |  |
| 129 | gui | hardcoded | player | sentence-fragments |  (offline) |  |
| 164 | gui | hardcoded | player |  | Players |  |
| 170 | gui | hardcoded | player |  |   (no players) |  |
| 182 | gui | hardcoded | player |  | Surfaces |  |
| 188 | gui | hardcoded | player |  |   (no surfaces yet) |  |
| 197 | gui | hardcoded | player | concat |   <surface name> | "  " .. info.name — info.name may itself be English built in teams_data.lua ("<Planet> base", platform name, r… |
| 200 | gui | hardcoded | player | concat |   (<location>) | "  (" .. info.location .. ")" — location may be "in transit", a capitalised internal planet name, or a space-l… |
| 213 | tooltip | hardcoded | player |  | View this surface in remote view | picked in Lua (own team) vs line 214 (foreign team) |
| 214 | tooltip | hardcoded | player |  | Spectate this surface (opens remote view; pauses your crafting while active) | picked in Lua (foreign team) |

## gui/team_settings.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 62 | gui | hardcoded | player | concat,rich-text | Team: <team_tag> | "Team: " .. team_tag — team_tag from helpers.team_tag, likely contains [color=] rich text |
| 70 | gui | hardcoded | player | rich-text | [color=1,0.65,0]Only your team leader can change these settings.[/color] |  |
| 83 | gui | hardcoded | player |  | Team name |  |
| 92 | tooltip | hardcoded | player | concat | Team name (max <N> characters) | "Team name (max " .. MAX_TEAM_NAME_LEN .. " characters)" |
| 101 | gui | hardcoded | player |  | <n> / <max> | string.format("%d / %d", #current_name, MAX_TEAM_NAME_LEN) — # is byte length, miscounts multibyte UTF-8; same… |
| 112 | gui | hardcoded | player |  | Save |  |
| 114 | tooltip | hardcoded | player | concat | Rename the team (leader only, max <N> chars) | "Rename the team (leader only, max " .. MAX_TEAM_NAME_LEN .. " chars)" |
| 121 | gui | hardcoded | player |  | Recruiting |  |
| 131 | gui | hardcoded | player | rich-text,newlines | [img=utility/warning_icon]  [color=1,0.85,0.2]New players can't find your team yet!\nClick "Sta… | static, but textually quotes the "Start recruiting" button caption (line 150) — the two must stay in sync when… |
| 142 | gui | hardcoded | player | rich-text | [color=0,1,0]Your team is visible to new players in the landing pen.[/color] | picked in Lua by is_lfm state (vs line 144) |
| 144 | gui | hardcoded | player | rich-text | [color=0.7,0.7,0.7]Your team is hidden from the landing pen join list.[/color] | picked in Lua by is_lfm state |
| 150 | gui | hardcoded | player |  | Stop recruiting | is_lfm and "Stop recruiting" or "Start recruiting" — picked in Lua |
| 150 | gui | hardcoded | player | sentence-fragments | Start recruiting | is_lfm and "Stop recruiting" or "Start recruiting" — picked in Lua; also quoted inside the line 131 banner |
| 153 | tooltip | hardcoded | player |  | Stop recruiting — your team will no longer appear in the landing pen. | picked in Lua by is_lfm state (vs line 154) |
| 154 | tooltip | hardcoded | player |  | Start recruiting — your team will appear in the landing pen join list. | picked in Lua by is_lfm state |
| 174 | gui | hardcoded | player |  | Team Settings | passed to helpers.add_title_bar (title caption built in scripts/helpers.lua) |
| 180 | tooltip | hardcoded | player |  | Close panel |  |
| 188 | gui | hardcoded | player |  | Team |  |
| 261 | tooltip | hardcoded | player |  | Open Team Settings |  |
| 326 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <team_tag> is looking for more players! | helpers.broadcast("[Team] " .. helpers.team_tag(force_name) .. " is looking for more players!") — one plain Lu… |
| 329 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <team_tag> is no longer recruiting. | helpers.broadcast("[Team] " .. helpers.team_tag(force_name) .. " is no longer recruiting.") |

## gui/teams.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 27 | gui | hardcoded | player |  | Teams — non-competitive | team_modifiers.is_active() and "Teams — non-competitive" or "Teams" — picked in Lua, passed to helpers.add_tit… |
| 27 | gui | hardcoded | player |  | Teams | frame-title variant picked in Lua (see above) |
| 36 | tooltip | hardcoded | player |  | Close panel |  |
| 84 | gui | hardcoded | player |  | No teams yet. |  |
| 189 | tooltip | hardcoded | player |  | Teams |  |

## gui/teams_data.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 17 | command | hardcoded | player | rich-text | [gps=%d,%d,%s] | string.format with hub position and surface name; stored in surface info consumed by /mts-players output via g… |
| 27 | gui | hardcoded | player |  | in transit | fallback when platform.space_location is nil; otherwise the internal space_location name is shown |
| 44 | gui | hardcoded | player | concat,sentence-fragments | <Planet> base | planet_disp .. " base" where planet_disp = planet:sub(1,1):upper() .. planet:sub(2) — English suffix concatena… |
| 46 | command | hardcoded | player | rich-text | [gps=0,0,%s] | string.format with surface name; same literal repeated at lines 65 and 81 |
| 79 | gui | hardcoded | player | concat,sentence-fragments | <Planet> base | planet_disp .. " base" (line 77 capitalisation of the base-planet key) — duplicate of the line 44 pattern for … |
| 149 | gui | hardcoded | player | sentence-fragments | just now | fmt_ago branch for < 1 minute; fmt_ago output is embedded into captions/tooltips across team_card.lua and stat… |
| 154 | gui | hardcoded | player | concat,sentence-fragments | <d>d ago | d .. "d ago" |
| 155 | gui | hardcoded | player | concat,sentence-fragments | <h>h <m>m ago | h .. "h " .. m .. "m ago" |
| 156 | gui | hardcoded | player | concat,sentence-fragments | <m>m ago | m .. "m ago" |
| 164 | gui | hardcoded | player | concat,sentence-fragments | <h>h <m>m | h .. "h " .. m .. "m" (fmt_playtime) |
| 165 | gui | hardcoded | player | concat,sentence-fragments | <m>m / < 1m | (m > 0 and m .. "m" or "< 1m") — two variants picked in Lua (fmt_playtime) |
| 193 | tooltip | hardcoded | player | sentence-fragments | online now | one of three `seen` variants picked in Lua (lines 193-194) |
| 194 | tooltip | hardcoded | player | concat,sentence-fragments | last seen: <ago> | "last seen: " .. fmt_ago(game.tick - t) |
| 194 | tooltip | hardcoded | player | sentence-fragments | never seen | fallback `seen` variant |
| 195 | tooltip | hardcoded | player | concat,rich-text,newlines,sentence-fragm… | [color=<hex>]<player>[/color]: Played <playtime> (<seen>) | "[color=" .. hex .. "]" .. p.name .. "[/color]: Played " .. fmt_playtime(p.online_time) .. " (" .. seen .. ")"… |
| 229 | gui | hardcoded | player | sentence-fragments | active | ago_text = any_online and "active" or fmt_ago(ago_ticks); embedded into " · <ago_text>" captions in team_card.… |

## gui/welcome.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 66 | gui | hardcoded | player |  | Same start. Different finish. |  |
| 73 | gui | hardcoded | player |  | What is Multi-Team Support? |  |
| 74 | gui | hardcoded | player |  | Each team races on their own copy of the world. Research independently, build separately, and c… | literal-only '..' concatenation across source lines (no runtime data) |
| 79 | gui | hardcoded | player |  | Teams & diplomacy |  |
| 80 | gui | hardcoded | player |  | Your team's force starts in cease-fire with all others. Other teams' surfaces are hidden until … | literal-only '..' concatenation; references the "Teams" panel title and 'friend' toggle label textually |
| 87 | gui | hardcoded | player |  | Space Age | section only rendered when space_age.is_active() |
| 88 | gui | hardcoded | player |  | Each team gets their own Nauvis, Vulcanus, Gleba, Fulgora, and Aquilo. No collisions, no shared… | literal-only '..' concatenation; hardcodes English planet names instead of localised planet names |
| 93 | gui | hardcoded | player |  | Navigation bar |  |
| 94 | gui | hardcoded | player | rich-text,newlines,sentence-fragments | [img=utility/gps_map_icon] Teams - members, surfaces, friend toggles, Follow Cam launchers, res… | literal-only '..' concatenation building a 7-line list; duplicates every nav-button title (must stay in sync w… |
| 103 | gui | hardcoded | player |  | Landing Pen |  |
| 104 | gui | hardcoded | player |  | New players wait in the Landing Pen until they are ready to spawn. Start a new team, or request… | literal-only '..' concatenation |
| 109 | gui | hardcoded | player |  | Records & announcements |  |
| 110 | gui | hardcoded | player |  | First-ever and fastest research wins, plus production milestones (science packs, landfill, plat… | literal-only '..' concatenation |
| 116 | gui | hardcoded | player |  | Commands |  |
| 117 | gui | hardcoded | player | newlines,sentence-fragments | /mts-teams — list teams with members and color\n/mts-players — list players and surfaces with G… | literal-only '..' concatenation building a 6-line list; command names must stay untranslated while description… |
| 157 | gui | hardcoded | player |  | Scan the QR code or copy the invite link below. |  |
| 180 | gui | hardcoded | player |  | <mts_discord_url setting value> | read-only text-box text = settings.global["mts_discord_url"].value — runtime setting value (a URL), not transl… |
| 205 | gui | hardcoded | player |  | Multi-Team Support |  |
| 215 | tooltip | hardcoded | player |  | Close |  |
| 246 | gui | hardcoded | player |  |   About   |  |
| 258 | gui | hardcoded | player |  |   Discord   |  |
| 309 | tooltip | hardcoded | player |  | About Multi-Team Support / Discord |  |

## milestones/engine.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 55 | flying-text | hardcoded | player | concat,rich-text,newlines,sentence-fragm… | <label>\n<threshold>x <item tag> | build_popup: label ("First!" / "New record!") .. "\n" .. threshold .. "x " .. helpers.item_rich_name(item_name… |
| 77 | chat | hardcoded | player | sentence-fragments,concat,rich-text,serv… | produce their first <item tag> | "produce their first " .. helpers.item_rich_name(item_name); returned by build_achievement_desc and spliced in… |
| 79 | chat | hardcoded | player | sentence-fragments,concat,rich-text,serv… | produce %d %s | string.format("produce %d %s", threshold, helpers.item_rich_name(item_name)); same fragment pipeline as line 7… |
| 88 | chat | hardcoded | player | concat,sentence-fragments,rich-text,serv… | %s %s was the first to %s! | string.format(fmt, team_modifiers.records_tag(), team_tag, achievement) — achievement is a build_achievement_d… |
| 95 | chat | hardcoded | player | concat,sentence-fragments,rich-text,serv… | %s %s is fastest to %s in %s (previous record: %s in %s) | string.format with records_tag, team_tag, achievement fragment, helpers.format_elapsed(new_elapsed), prev team… |
| 131 | flying-text | hardcoded | player | sentence-fragments | First! | passed as label into build_popup, joined with "\n" + count + item tag |
| 135 | external | hardcoded | external | server-side-string,discord-mirror,concat… | %s was the first to %s | string.format(fmt, team_name, plain(achievement)) — Discord payload text for mts.milestone_first; plain() stri… |
| 146 | flying-text | hardcoded | player | sentence-fragments | New record! | passed as label into build_popup, joined with "\n" + count + item tag |
| 155 | external | hardcoded | external | server-side-string,discord-mirror,concat… | %s is now fastest to %s in %s (previous: %s in %s) | string.format with team_name, plain(achievement), helpers.format_elapsed(elapsed) x2, prev team name — Discord… |
| 230 | chat | hardcoded | player | sentence-fragments | reach | default verb when a consumer mod's spec.verb is nil; concatenated into external-milestone achievement sentence… |
| 232 | chat | hardcoded | player | sentence-fragments,concat,server-side-st… | <verb> their first <noun> | verb .. " their first " .. spec.noun — verb/noun supplied in English by the consumer mod via remote mts-v1 reg… |
| 234 | chat | hardcoded | player | sentence-fragments,concat,plural,server-… | %s %d %s (noun .. "s") | string.format("%s %d %s", verb, threshold, spec.noun .. "s") — pluralises by blindly appending "s" to the cons… |
| 251 | flying-text | hardcoded | player | plural,concat,sentence-fragments | <threshold> <noun>s | popup_detail = first_only and spec.noun or (threshold .. " " .. spec.noun .. "s") — appended-"s" plural; used … |
| 255 | flying-text | hardcoded | player | concat,newlines | First!\n<detail> | "First!\n" .. popup_detail, rendered by pop_text.milestone for the whole force |
| 259 | external | hardcoded | external | server-side-string,discord-mirror,concat… | %s was the first to %s | string.format(fmt, team_name, achievement) — Discord payload text for external (consumer-reported) mts.milesto… |
| 266 | flying-text | hardcoded | player | concat,newlines | New record!\n<detail> | "New record!\n" .. popup_detail, rendered by pop_text.milestone for the whole force |
| 275 | external | hardcoded | external | server-side-string,discord-mirror,concat… | %s is now fastest to %s in %s (previous: %s in %s) | string.format with team_name, achievement, helpers.format_elapsed x2, prev team name — Discord payload text fo… |
| 291 | chat | hardcoded | player | sentence-fragments | reach | second occurrence of the default verb, stored into storage.milestone_external when registering a consumer mile… |

## prototypes/connections.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 39 | error | hardcoded | player |  | connections.lua: no space-connection prototypes loaded |  |
| 138 | prototype | partial | player | concat | " (Team " .. slot .. ")" appended to {"space-connection-name.<base>"} | localised_name = {"", {"space-connection-name." .. info.name}, " (Team " .. slot .. ")"} — locale key assemble… |

## prototypes/entities/passivize-radars.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 59 | prototype | localised | player |  | entity-name.mts-passivized-radar-prefix | parameterized locale key: {"entity-name.mts-passivized-radar-prefix", orig_name} where orig_name is the radar'… |
| 60 | prototype | localised | player |  | entity-description.mts-passivized-radar |  |
| 71 | prototype | localised | player |  | entity-name.mts-passivized-radar-prefix | same parameterized key applied to placer item prototypes whose place_result is the clamped radar; parameter is… |

## prototypes/planets.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 38 | error | hardcoded | player |  | planets.lua: data.raw.planet is missing |  |
| 99 | prototype | partial | player | concat | " " .. slot appended to {"space-location-name.<base>"} | localised_name = {"", {"space-location-name." .. base_name}, " " .. slot} — locale key built by concatenating … |
| 102 | prototype | localised | player |  | space-location-description.<base> | locale key assembled as "space-location-description." .. base_name; a modded planet lacking that key yields an… |

## scripts/admin_flags.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 27 | gui | hardcoded | admin |  | Landing Pen |  |
| 28 | tooltip | hardcoded | admin |  | When enabled, new players wait in the Landing Pen before spawning into the game. |  |
| 32 | gui | hardcoded | admin |  | Multi-player teams |  |
| 33 | tooltip | hardcoded | admin |  | When enabled, players in the Landing Pen can request to join an existing team. |  |
| 37 | gui | hardcoded | admin |  | Allow Friendship |  |
| 38 | tooltip | hardcoded | admin |  | When enabled, players can send friend requests. Disabling breaks all existing friendships. |  |
| 42 | gui | hardcoded | admin |  | Spectate Notifications |  |
| 43 | tooltip | hardcoded | admin |  | When enabled, all players are notified when someone starts or stops spectating. |  |
| 47 | gui | hardcoded | admin |  | Text Popups |  |
| 48 | tooltip | hardcoded | admin |  | When enabled, animated text popups appear on spawn, team join, milestones, and player death. |  |
| 52 | gui | hardcoded | admin |  | Individual Chat Mode |  |
| 53 | tooltip | hardcoded | admin | sentence-fragments | When enabled, each player sets their own global/team chat mode instead of the whole team switch… |  |
| 57 | gui | hardcoded | admin |  | Allow Blueprint Imports |  |
| 58 | tooltip | hardcoded | admin |  | When enabled, players can import external blueprints via chat strings, the blueprint library, a… |  |
| 62 | gui | hardcoded | admin |  | Staged Start (Speedrun) |  |
| 63 | tooltip | hardcoded | admin | sentence-fragments | When enabled, a new team's clock does not start until the leader clicks "Start Playing". The te… |  |
| 67 | gui | hardcoded | admin |  | Readable Player Colours |  |
| 68 | tooltip | hardcoded | admin |  | When enabled, players' colours are automatically kept readable and distinct: dark colours are b… |  |
| 72 | gui | hardcoded | admin |  | Non-competitive Mode |  |
| 73 | tooltip | hardcoded | admin |  | When enabled, admins can give individual teams easier settings via per-team modifiers (e.g. pea… |  |
| 237 | chat | hardcoded | player | concat,sentence-fragments,rich-text,serv… | x  | item.count .. "x " .. helpers.item_rich_name(item.name) — builds per-item fragments like "5x [item=iron-plate]… |
| 241 | chat | hardcoded | player | sentence-fragments,server-side-string | Admin | fallback actor name when admin_player is nil; otherwise helpers.colored_name(admin_player.name, chat_color) |
| 242 | chat | hardcoded | player | concat,rich-text,server-side-string | <who> added <count>x <item>, ... to the starter items list. | who .. " added " .. table.concat(parts, ", ") .. " to the starter items list." — actor name (colored) + item-l… |
| 322 | log | hardcoded | log-only | concat,plural | [multi-team-support] auto-populated starter items from <player> (<n> item types) | "[multi-team-support] auto-populated starter items from " .. player.name .. " (" .. #storage.starter_items .. … |

## scripts/chat_channel.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 110 | chat | hardcoded | player | sentence-fragments,rich-text,server-side… | TEAM-ONLY | picked by ternary (to_local), wrapped in helpers.colored_name(word, M.LOCAL_COLOR) -> [color=] rich text, inte… |
| 110 | chat | hardcoded | player | sentence-fragments,rich-text,server-side… | GLOBAL | picked by ternary (not to_local), wrapped in helpers.colored_name(word, M.GLOBAL_COLOR) -> [color=] rich text,… |
| 114 | chat | hardcoded | player | concat,rich-text,server-side-string | Your chat is now <STATE>. | "Your chat is now " .. state .. "." — state is the colored TEAM-ONLY/GLOBAL word; a suffix sentence (line 121 … |
| 115 | chat | hardcoded | player | concat,rich-text,server-side-string | Team chat is now <STATE> (switched by <name>). | "Team chat is now " .. state .. " (switched by " .. (colored switcher name or "an admin") .. ")." — then a suf… |
| 118 | chat | hardcoded | player | sentence-fragments,server-side-string | an admin | fallback for the switcher name inside the line-115 sentence when switcher is nil |
| 121 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… |  Messages stay within your team; start a message with ! to shout globally. | appended to subject via .. when switching to team-only (literal split across lines 121-122) |
| 124 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… |  Everyone on the server sees your messages. | appended to subject via .. when switching to global |

## scripts/chat_tag.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 49 | other | hardcoded | player | rich-text,server-side-string | GLOBAL | badge() at line 43 formats it as [color=r,g,b][font=count-font][GLOBAL][/font][/color] once at parse time; ass… |
| 50 | other | hardcoded | player | rich-text,server-side-string | TEAM | badge() at line 43 formats it as [color=r,g,b][font=count-font][TEAM][/font][/color] once at parse time; assig… |

## scripts/chunk_trim.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 57 | command | hardcoded | player | concat,rich-text,server-side-string | <label> (<surface>): no team force; skipped | label .. " (" .. surface.name .. "): no team force; skipped" — label is helpers.team_tag(force) or surface.nam… |
| 123 | command | hardcoded | player | concat,rich-text,server-side-string | %s (%s): deleted %d / %d chunks (kept %d) | string.format with team label (helpers.team_tag, may embed rich text), surface.name, deleted, total, total-del… |
| 149 | command | hardcoded | admin | server-side-string | Trim already in progress. | returned as error_msg string from chunk_trim.start; printed by /mts-trim handler (commands/admin.lua:242) via … |
| 161 | command | hardcoded | admin | concat,server-side-string | No team surfaces found for <team-N>. | "No team surfaces found for " .. opts.team_force .. "." — returned as error_msg, printed by /mts-trim handler |
| 162 | command | hardcoded | admin | server-side-string | No team surfaces found. | returned as error_msg, printed by /mts-trim handler |
| 181 | command | hardcoded | player | plural,server-side-string | Chunk trim complete across %d surface(s). | ("...%d surface(s)."):format(#q.surfaces); notify() falls back to game.print when caller disconnected |

## scripts/color_fix.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 174 | chat | hardcoded | player |  | Your colour was adjusted to stay readable and distinct from other players. |  |
| 217 | chat | hardcoded | player | concat,server-side-string | [colour] Adjusted unreadable / clashing colours for: <names> | "[colour] Adjusted unreadable / clashing colours for: " .. table.concat(names, ", ") — broadcast to all player… |
| 219 | command | hardcoded | admin | plural | Adjusted %d player(s). | ("Adjusted %d player(s)."):format(#names) — printed to the /mts-fixcolors caller |

## scripts/commands/admin.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 37 | command | hardcoded | admin |  | Team no longer exists. |  |
| 41 | command | hardcoded | admin |  | That team slot is no longer occupied. |  |
| 49 | command | hardcoded | admin | concat | Team slot <slot> has been recycled by a different team since the dialog was opened. Re-run /mts… | "Team slot " .. slot .. " has been recycled..." .. " the dialog was opened..." — slot number interpolated, lit… |
| 71 | chat | hardcoded | player | concat,rich-text,server-side-string | Your team <tag> has been disbanded by an admin. | "Your team " .. team_tag .. " has been disbanded by an admin." — team_tag from helpers.team_tag_with_leader (e… |
| 83 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <tag> has been disbanded by an admin. | "[Team] " .. team_tag .. " has been disbanded by an admin." — broadcast to all players via helpers.broadcast |
| 86 | command | hardcoded | admin | concat,rich-text | Disbanded <tag>. | "Disbanded " .. team_tag .. "." |
| 94 | command | hardcoded | player |  | mts-disband |  |
| 95 | command | hardcoded | player |  | Disband a team and free the slot (admin only). Usage: /mts-disband <team-N> |  |
| 98 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 99 | command | hardcoded | player |  | Only admins can disband teams. |  |
| 103 | command | hardcoded | admin |  | Usage: /mts-disband <team-N>  (e.g. /mts-disband team-3) |  |
| 109 | command | hardcoded | admin |  | Invalid team. Use team name (team-3) or slot number (3). |  |
| 113 | command | hardcoded | admin | concat | Team '<name>' does not exist. | "Team '" .. force_name .. "' does not exist." |
| 116 | command | hardcoded | admin | concat | Team slot <slot> is not occupied. | "Team slot " .. slot .. " is not occupied." |
| 128 | gui | hardcoded | admin | concat,rich-text,symbol-only,sentence-fr… | ★  | "\xE2\x98\x85 " .. helpers.colored_name(leader.name, chat_color) — leader line inside the disband confirm dial… |
| 129 | gui | hardcoded | admin | sentence-fragments | (no leader) | fallback leader line when no valid leader |
| 132 | gui | hardcoded | admin | sentence-fragments | online now | picked when activity.any_online; otherwise activity.ago_text (built in gui/teams_data.lua, outside this scan) |
| 133 | gui | hardcoded | admin | sentence-fragments | never | fallback last-active value when activity is nil |
| 135 | gui | hardcoded | admin | concat,rich-text | Disband <tag> (slot <n>)? | "Disband " .. helpers.team_tag(force_name) .. " (slot " .. slot .. ")?" — confirm dialog title |
| 136 | gui | hardcoded | admin | concat,plural,newlines,rich-text | Team: <tag>\nSlot: #<n> (<force>)\nLeader: <line>\nLast active: <when>\n\n• <count> player[s] w… | long .. chain (lines 136-143) interpolating team tag, slot, force_name, leader line, last-active fragment, and… |
| 144 | gui | hardcoded | admin |  | Disband Team |  |
| 145 | gui | hardcoded | admin |  | Cancel |  |
| 154 | command | hardcoded | player |  | mts-resume |  |
| 155 | command | hardcoded | player |  | Resume a team's entities after /mts-pause (admin only). Usage: /mts-resume <team-N> |  |
| 158 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 159 | command | hardcoded | player |  | Only admins can force-resume teams. |  |
| 163 | command | hardcoded | admin |  | Usage: /mts-resume <team-N>  (e.g. /mts-resume team-11) |  |
| 169 | command | hardcoded | admin | concat | Team '<param>' does not exist. | "Team '" .. param .. "' does not exist." |
| 172 | command | hardcoded | admin | concat | Could not resume <force> (not a team force). | "Could not resume " .. force_name .. " (not a team force)." |
| 174 | command | hardcoded | admin | concat,rich-text | Resume sweep started for <tag>. Entities will be re-activated over the next few ticks. | "Resume sweep started for " .. helpers.team_tag_with_leader(force_name) .. ". Entities will be re-activated ov… |
| 178 | command | hardcoded | player |  | mts-pause |  |
| 179 | command | hardcoded | player |  | Pause a team's entities (admin only). Stops production AND defenses. Usage: /mts-pause <team-N> |  |
| 182 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 183 | command | hardcoded | player |  | Only admins can force-pause teams. |  |
| 187 | command | hardcoded | admin |  | Usage: /mts-pause <team-N>  (e.g. /mts-pause team-11) |  |
| 193 | command | hardcoded | admin | concat | Team '<param>' does not exist. | "Team '" .. param .. "' does not exist." |
| 196 | command | hardcoded | admin | concat | Could not pause <force> (not a team force). | "Could not pause " .. force_name .. " (not a team force)." |
| 198 | command | hardcoded | admin | concat,rich-text | Pause sweep started for <tag>. Entities will be deactivated over the next few ticks. Run /mts-r… | .. chain (lines 198-200) interpolating helpers.team_tag_with_leader(force_name) and force_name into the /mts-r… |
| 203 | command | hardcoded | player |  | mts-trim |  |
| 204 | command | hardcoded | player |  | Trim unused chunks on all team surfaces, every planet (admin only). Usage: /mts-trim [team-N] [… |  |
| 207 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 208 | command | hardcoded | player |  | Only admins can trim chunks. |  |
| 222 | command | hardcoded | admin |  | entity_buffer must be a number between 0 and 100. |  |
| 228 | command | hardcoded | admin |  | player_buffer must be a number between 0 and 100. |  |
| 233 | command | hardcoded | admin | concat | Team '<team>' does not exist. | "Team '" .. team_force .. "' does not exist." |
| 242 | command | hardcoded | admin |  | Could not start trim. | fallback when chunk_trim.start returns no error string (caller.print(err or "Could not start trim.")) |
| 243 | command | hardcoded | admin | plural | Chunk trim queued for %d surface(s). Processing one surface every ~0.5s. | ("..."):format(count) |
| 246 | command | hardcoded | player |  | mts-fixcolors |  |
| 247 | command | hardcoded | player |  | Brighten unreadable (too dark) player name colours now (admin only). Runs automatically on join… |  |
| 250 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 251 | command | hardcoded | player |  | Only admins can fix player colours. |  |

## scripts/commands/debug_cmd.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 8 | command | hardcoded | admin | newlines,sentence-fragments | /mts-debug research <tech> [--players a,b,c] [--delay N]\n    Run tech:research_recursive() on … | DEBUG_HELP: six literals (lines 9-14) joined with table.concat(..., "\n"); printed for 'help' subcommand (line… |
| 42 | command | hardcoded | admin | concat | Player '<name>' not found. | "Player '" .. name .. "' not found." |
| 51 | command | hardcoded | player |  | mts-debug |  |
| 52 | command | hardcoded | player |  | Schedule debug actions (admin only). Use /mts-debug help for usage. |  |
| 55 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 56 | command | hardcoded | player |  | Only admins can use /mts-debug. |  |
| 66 | command | hardcoded | admin |  | [mts-debug] No tasks queued. |  |
| 67 | command | hardcoded | admin | newlines,sentence-fragments | [mts-debug] Tasks: | header line; row lines appended and the block printed as table.concat(lines, "\n") |
| 69 | command | hardcoded | admin | concat,sentence-fragments |   #%d  %s  %s  (%s) | string.format(row, r.id, r.kind, r.label, r.detail) — kind/label/detail are English strings built in scripts/d… |
| 78 | command | hardcoded | admin |  | Usage: /mts-debug stop <id\|all> |  |
| 81 | command | hardcoded | admin | concat,plural | [mts-debug] Stopped <n> task(s). | "[mts-debug] Stopped " .. n .. " task(s)." |
| 84 | command | hardcoded | admin | concat | Invalid task id: <arg> | "Invalid task id: " .. arg |
| 86 | command | hardcoded | admin | concat | [mts-debug] Stopped task #<id>. | "[mts-debug] Stopped task #" .. id .. "." |
| 88 | command | hardcoded | admin | concat | [mts-debug] No such task: #<id>. | "[mts-debug] No such task: #" .. id .. "." |
| 98 | command | hardcoded | admin |  | Usage: /mts-debug research <tech> [--players a,b,c] [--delay N] |  |
| 105 | command | hardcoded | admin |  | --delay must be a non-negative integer (ticks). |  |
| 120 | command | hardcoded | admin | concat | Technology '<tech>' not found on any of the target forces. | "Technology '" .. tech_name .. "' not found on any of the target forces." (literal split across lines 120-121) |
| 128 | command | hardcoded | admin | concat,sentence-fragments,newlines |   +%d ticks: %s | string.format per force: (i-1)*delay tick offset and force name; joined with "\n" into the line-130 summary |
| 131 | command | hardcoded | admin | concat,plural,newlines | [mts-debug] Scheduled task #%d: research %s on %d force(s):\n%s | string.format(id, tech_name, #force_names, table.concat(plan, "\n")) |
| 136 | command | hardcoded | admin | concat,newlines | Unknown subcommand: <sub> | "Unknown subcommand: " .. sub .. "\n" .. DEBUG_HELP |

## scripts/commands/team.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 20 | command | hardcoded | player |  | You are already in the Landing Pen. |  |
| 29 | command | hardcoded | player |  | You have left your team. |  |
| 38 | command | hardcoded | player |  | Kick target is no longer available. |  |
| 42 | command | hardcoded | player |  | You are no longer the team leader. |  |
| 46 | command | hardcoded | player | concat,rich-text | <name> is no longer on your team. | helpers.colored_name(target.name, chat_color) .. " is no longer on your team." |
| 54 | chat | hardcoded | player | concat,rich-text,server-side-string | You have been kicked from <tag> by <leader>. | "You have been kicked from " .. team_tag .. " by " .. helpers.colored_name(leader.name, chat_color) .. "." — p… |
| 56 | command | hardcoded | player | concat,rich-text | Kicked <name> from <tag>. | "Kicked " .. colored_name .. " from " .. team_tag .. "." — printed to the leader |
| 68 | command | hardcoded | player |  | t |  |
| 69 | command | hardcoded | player |  | Send a message to your team only. Usage: /t <message> |  |
| 75 | command | hardcoded | player |  | Usage: /t <message>  — sends to your team only. |  |
| 78 | chat | hardcoded | player | rich-text,sentence-fragments,server-side… | [color=0.60,0.86,0.39][Team][/color]  | prefix label concatenated into the /t relay line at line 82 |
| 82 | chat | hardcoded | player | concat,rich-text,server-side-string | <[Team] label><name>: <message> | label .. name .. ": " .. msg — colored sender name plus raw player message, printed to every connected teammat… |
| 87 | command | hardcoded | player |  | mts-players |  |
| 88 | command | hardcoded | player |  | List all players, their bases, and platform locations |  |
| 92 | command | hardcoded | player | newlines,sentence-fragments | [All Players] | header of a multi-line listing joined with "\n" (line 102); falls back to game.print when run from server cons… |
| 95 | command | hardcoded | player | concat,rich-text,sentence-fragments | <team_tag>: | helpers.team_tag(info.force_name) .. ":" |
| 97 | command | hardcoded | player | concat,rich-text,sentence-fragments |   [color=0.7,0.7,0.7]<surface>[/color] <gps>  @  <location> | "  [color=0.7,0.7,0.7]" .. surface_info.name .. "[/color] " .. surface_info.gps .. "  @  " .. surface_info.loc… |
| 101 | command | hardcoded | player |  |   No players found. |  |
| 106 | command | hardcoded | player |  | mts-leave |  |
| 107 | command | hardcoded | player |  | Leave your current team and return to the Landing Pen |  |
| 110 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 112 | command | hardcoded | player |  | You are already in the Landing Pen. |  |
| 115 | gui | hardcoded | player | concat,rich-text | Leave <tag>? | "Leave " .. helpers.team_tag(caller.force.name) .. "?" — confirm dialog title |
| 116 | gui | hardcoded | player | newlines | Are you sure you want to leave your team?\n\n• You will return to the Landing Pen and lose your… | .. chain of literals (lines 116-121); static overall, with manual line-wrapping baked into the text |
| 122 | gui | hardcoded | player |  | Leave Team |  |
| 123 | gui | hardcoded | player |  | Cancel |  |
| 128 | command | hardcoded | player |  | mts-rename |  |
| 129 | command | hardcoded | player |  | Rename your team (team leader only). Usage: /mts-rename <new name> |  |
| 132 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 138 | command | hardcoded | player |  | Usage: /mts-rename <new name> |  |
| 144 | command | hardcoded | player |  | mts-teams |  |
| 145 | command | hardcoded | player |  | List all teams with their members and status |  |
| 148 | command | hardcoded | player | newlines,sentence-fragments | [Teams] | header of a multi-line listing joined with "\n" (line 171); falls back to game.print from server console |
| 155 | command | hardcoded | player | concat,rich-text |   [color=0.55,0.55,0.55][%s] (unclaimed)[/color] | string.format with force_name |
| 162 | command | hardcoded | player | rich-text,symbol-only,sentence-fragments | [color=0.7,0.7,0.7]?[/color] | fallback leader display when the stored leader player cannot be resolved |
| 165 | command | hardcoded | player | concat,plural,rich-text |   [color=0.55,0.55,0.55][%s][/color] %s — leader: %s, %d player%s | string.format(force_name, helpers.team_tag(force_name), leader_str, count, count == 1 and "" or "s") — Lua plu… |
| 175 | command | hardcoded | player |  | mts-chat |  |
| 176 | command | hardcoded | player |  | Toggle your chat between team-only and global (same as the HUD switch) |  |
| 180 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 185 | command | hardcoded | player |  | mts-modifiers |  |
| 186 | command | hardcoded | player |  | Show each team's gameplay modifiers (non-competitive mode) |  |
| 191 | command | hardcoded | player |  | [Modifiers] This server is in standard competitive mode — every team plays under identical sett… | two literals joined by .. (lines 191-192); static overall |
| 194 | command | hardcoded | player | rich-text | [Modifiers] [color=1,0.65,0]NON-COMPETITIVE mode[/color] — teams may play under different setti… | two literals joined by .. (lines 194-195); static overall |
| 201 | command | hardcoded | player | concat,rich-text,sentence-fragments |   %s%s — %s | string.format(helpers.team_tag_with_leader(force_name), badge and (" " .. badge) or "", desc and ("[color=1,0.… |
| 205 | command | hardcoded | player | sentence-fragments | standard | fallback modifier description inside the line-201 row format |
| 213 | command | hardcoded | player |  | mts-kick |  |
| 214 | command | hardcoded | player |  | Kick a player from your team (team leader only). Usage: /mts-kick <player-name> |  |
| 217 | command | hardcoded | player | server-side-string | This command can only be used by a player. |  |
| 219 | command | hardcoded | player |  | Only the team leader can kick players. |  |
| 222 | command | hardcoded | player |  | You are the only player on your team. |  |
| 226 | command | hardcoded | player |  | Usage: /mts-kick <player-name> |  |
| 231 | command | hardcoded | player | concat | Player '<name>' not found. | "Player '" .. target_name .. "' not found." |
| 234 | command | hardcoded | player |  | You cannot kick yourself. Use /mts-leave instead. |  |
| 237 | command | hardcoded | player | concat,rich-text | <name> is not on your team. | helpers.colored_name(target.name, chat_color) .. " is not on your team." |
| 241 | gui | hardcoded | player | concat | Kick <name>? | "Kick " .. target.name .. "?" — confirm dialog title |
| 242 | gui | hardcoded | player | concat,rich-text,newlines | Are you sure you want to kick <name> from <tag>?\n\n• They will return to the Landing Pen and l… | .. chain (lines 242-247) interpolating helpers.colored_name(target) and helpers.team_tag(caller.force.name); m… |
| 248 | gui | hardcoded | player |  | Kick Player |  |
| 249 | gui | hardcoded | player |  | Cancel |  |

## scripts/debug.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 55 | command | hardcoded | admin | concat,sentence-fragments | research %s × %d (delay %d) | string.format(tech, #force_names, delay_ticks or 0) at schedule time; PERSISTED in storage.debug.tasks[id].lab… |
| 87 | command | hardcoded | admin | concat,plural,sentence-fragments | <n> action(s) queued | (#task.actions) .. " action(s) queued" — returned as row.detail, shown in the /mts-debug list row format (debu… |
| 107 | log | hardcoded | log-only | concat | [mts-debug] <error> | log("[mts-debug] " .. tostring(err)) — pcall error from a scheduled action |

## scripts/force_utils.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 101 | log | hardcoded | log-only | concat | bounce_if_foreign: TELEPORT → {home.name} (home) | "bounce_if_foreign: TELEPORT → " .. home.name .. " (home)"; passed to helpers.diag which prepends "[multi-team… |
| 109 | log | hardcoded | log-only |  | bounce_if_foreign: TELEPORT → landing-pen (fallback) | static literal, but helpers.diag wraps it with the [multi-team-support:DIAG] prefix and player-state suffix |
| 121 | log | hardcoded | log-only | concat | [multi-team-support] clock started for {player.name} at tick {game.tick} | "[multi-team-support] clock started for " .. player.name .. " at tick " .. game.tick |

## scripts/global_milestones.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 146 | external | hardcoded | external | server-side-string,discord-mirror,concat | %s launched a rocket (total: %d) | string.format with team display name (storage.team_names custom name or raw force name) and the rounded launch… |
| 155 | chat | hardcoded | player | sentence-fragments,concat | A team | fallback subject used when helpers.team_tag_with_leader(force.name) returns nil; concatenated into the first-r… |
| 156 | chat | hardcoded | player | concat,rich-text,server-side-string |  launched the first rocket into space! | team_tag .. " launched the first rocket into space!" where team_tag = helpers.team_tag_with_leader (rich-text … |
| 204 | chat | hardcoded | player | rich-text,sentence-fragments,server-side… | [planet={pname}] | "[planet=" .. pname .. "]" fragment (canonical base planet name) built for the first-landing announcement |
| 206 | chat | hardcoded | player | concat,rich-text,server-side-string |  was first to set foot on {planet_tag}! | team_tag .. " was first to set foot on " .. planet_tag .. "!"; routed through announce() -> helpers.broadcast … |

## scripts/helpers.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 108 | log | hardcoded | log-only |  | %s force=%s surface=%s pos=%s phys_surface=%s phys_pos=%s ctrl=%s char=%s opened=%s near=%s hub… | string.format of full player state; feeder fragments include "?" fallbacks (lines 35, 60, 111, 114), "nil" fal… |
| 127 | log | hardcoded | log-only | concat | [multi-team-support:DIAG] {context} \| {player_state} | "[multi-team-support:DIAG] " .. context .. " \| " .. helpers.player_state(player); always-on (no debug gate), … |
| 157 | other | hardcoded | player | server-side-string,sentence-fragments | %dh %02dm %02ds | string.format from tick count in helpers.fmt_duration; returned as a fragment consumed by player-facing chat/G… |
| 158 | other | hardcoded | player | server-side-string,sentence-fragments | %dm %02ds | string.format in helpers.fmt_duration (minutes branch) |
| 159 | other | hardcoded | player | server-side-string,sentence-fragments | %ds | string.format in helpers.fmt_duration (seconds branch) |
| 169 | other | hardcoded | player | server-side-string,sentence-fragments | %dh %02dm | string.format in helpers.fmt_duration_coarse (minute-resolution, rounds to nearest minute); used for slow-refr… |
| 170 | other | hardcoded | player | server-side-string,sentence-fragments | %dm | string.format in helpers.fmt_duration_coarse (minutes-only branch) |
| 194 | other | hardcoded | player | symbol-only | ? | fallback return of helpers.display_surface_name when surface_name is nil; the function otherwise returns a cap… |
| 213 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… | Team  | "Team " .. helpers.display_name(force_name), skipped when the display name already starts with "team" (case-in… |
| 246 | chat | hardcoded | player | rich-text,symbol-only,sentence-fragments… |  [color=0.7,0.7,0.7][[/color]{leader}[color=0.7,0.7,0.7]][/color] | team_tag .. dim-grey bracket fragments (lines 246-248) around helpers.colored_name(leader.name, leader.chat_co… |
| 250 | chat | hardcoded | player | rich-text,symbol-only,sentence-fragments… |  [color=0.7,0.7,0.7][?][/color] | no-leader fallback suffix: tag .. literal |
| 265 | other | hardcoded | player | rich-text,sentence-fragments,concat | [item={item_name}] | "[item=" .. item_name .. "]" in helpers.item_rich_name; falls through to fluid tag or the raw name when no pro… |
| 268 | other | hardcoded | player | rich-text,sentence-fragments,concat | [fluid={item_name}] | "[fluid=" .. item_name .. "]" fluid branch of helpers.item_rich_name |
| 276 | other | hardcoded | player | rich-text,sentence-fragments,concat | [technology={tech_name}] | "[technology=" .. tech_name .. "]" in helpers.tech_rich_name |
| 282 | chat | hardcoded | player | rich-text,sentence-fragments,concat,serv… |  [color=0.50,0.50,0.50]({force_name})[/color] | " [color=0.50,0.50,0.50](" .. force_name .. ")[/color]" in helpers.force_tag; grey suffix appended to chat mes… |
| 288 | other | hardcoded | player | rich-text,server-side-string,sentence-fr… | [color=%.2f,%.2f,%.2f]%s[/color] | string.format in helpers.colored_name with r/g/b components and a name; the universal rich-text colouring wrap… |
| 303 | other | hardcoded | player | symbol-only | ? | fallback return of helpers.format_elapsed for nil/negative tick counts |
| 309 | other | hardcoded | player | server-side-string,sentence-fragments | %dh %dm | string.format in helpers.format_elapsed (hours branch); tick-to-time formatting for player-facing displays |
| 311 | other | hardcoded | player | server-side-string,sentence-fragments | %dm %ds | string.format in helpers.format_elapsed (minutes branch) |
| 313 | other | hardcoded | player | server-side-string,sentence-fragments | %ds | string.format in helpers.format_elapsed (seconds branch) |
| 391 | gui | hardcoded | player |  | show offline |  |
| 399 | tooltip | hardcoded | player |  | Hide offline teams | Lua conditional `show_offline and "Hide offline teams" or "Show offline teams"` picks the tooltip by checkbox … |
| 399 | tooltip | hardcoded | player |  | Show offline teams | other arm of the same conditional tooltip expression |
| 450 | gui | localised | player |  | {"", tech.localised_name, " ", label} | LocalisedString composition in helpers.tech_label appending a completed-level number to the technology's local… |

## scripts/pause/power.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 37 | log | hardcoded | debug | concat | [mts:pause/power:DIAG] {msg} | "[mts:pause/power:DIAG] " .. msg; gated behind local DIAG = false |
| 168 | log | hardcoded | debug |  | %s force=%s touched=%d sources{%s} | string.format with a conditional literal "THAW"/"FREEZE" (line 169), force name, touched count, and table.conc… |

## scripts/pause/wires.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 56 | log | hardcoded | debug | concat | [mts:pause/wires:DIAG] {msg} | "[mts:pause/wires:DIAG] " .. msg; gated behind local DIAG = false |
| 137 | log | hardcoded | debug | concat | CUT begin force={name} SA={bool} #surfaces={n} | "CUT begin force=" .. tostring(force.name) .. " SA=" .. tostring(sa) .. " #surfaces=" .. count; DIAG-gated |
| 139 | log | hardcoded | debug |  | CUT skip: not Space Age |  |
| 155 | log | hardcoded | debug | concat | surface={name} poles={n} | "surface=" .. surface.name .. " poles=" .. #poles; DIAG-gated |
| 167 | log | hardcoded | debug |  | pole#%s conn_ok=%s connections_n=%s real_n=%s | string.format with unit number, pcall results, and "?(" .. type(list) .. ")" fallback fragments; DIAG-gated, f… |
| 178 | log | hardcoded | debug |  |   conn#%d target=%s owner_type=%s far_unit=%s origin=%s | string.format with connection fields; DIAG-gated, first 10 connections only |
| 197 | error | hardcoded | debug | concat | disconnect_from ERR: {err} | "disconnect_from ERR: " .. tostring(cerr); DIAG-gated, first failure only |
| 205 | log | hardcoded | debug | concat | pole#{unit} conn=NIL (copper_connector returned nil) | "pole#" .. tostring(a_unit) .. " conn=NIL (copper_connector returned nil)"; DIAG-gated |
| 212 | log | hardcoded | debug |  | CUT done force=%s total_poles=%d total_conns=%d cut=%d recorded=%d | string.format; DIAG-gated |
| 215 | log | hardcoded | log-only | concat,plural | [multi-team-support:pause/wires] cut {n} pole connections for {force_name} | "[multi-team-support:pause/wires] cut " .. cut_count .. " pole connections for " .. force.name; always-on log(… |
| 231 | log | hardcoded | debug | concat | RECONNECT begin force={name} recorded_pairs={n} | "RECONNECT begin force=" .. force.name .. " recorded_pairs=" .. count; DIAG-gated |
| 290 | log | hardcoded | log-only | concat | [multi-team-support:pause/wires] reconnect complete: {force_name} | "[multi-team-support:pause/wires] reconnect complete: " .. name; always-on log() |

## scripts/planet_map.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 366 | log | hardcoded | log-only | concat | [multi-team-support:planet_map] discovery techs detected: {""\|none} | prefix .. (next(storage.discovery_tech_map) and "" or "none") — conditional literal "none" concatenated in |
| 369 | log | hardcoded | log-only | concat |   {tech_name} -> {base} | "  " .. tech_name .. " -> " .. base, one log line per discovery tech |
| 464 | error | hardcoded | log-only | concat | [multi-team-support:planet_map] logistic rewrite failed: {err} force={force} {current} -> {own} | prefix .. tostring(err) .. " force=" .. force.name .. " " .. current .. " -> " .. own |
| 469 | log | hardcoded | log-only | concat | [multi-team-support:planet_map] logistic rewrite: force={force} {current} -> {own} on {entity.n… | concatenation of force name, source/destination planet variant names, and entity name |
| 477 | flying-text | hardcoded | player | concat,rich-text,symbol-only,server-side… | [color=1,0.55,0.35]{current}[/color] → [color=0.45,0.9,0.45]{own}[/color] | "[color=1,0.55,0.35]" .. current .. "[/color]" .. " → " .. "[color=0.45,0.9,0.45]" .. own .. "[/color]" passed… |

## scripts/pop_text.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 269 | flying-text | hardcoded | player | server-side-string | RIP! |  |

## scripts/pre_start.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 124 | log | hardcoded | log-only | concat | [multi-team-support] pre_start committed for {force_name} at tick {game.tick} | "[multi-team-support] pre_start committed for " .. force_name .. " at tick " .. game.tick |
| 136 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] {team_tag} has started playing! | "[Team] " .. helpers.team_tag(force_name) .. " has started playing!" via helpers.broadcast (player.print to ev… |

## scripts/remote_api.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 272 | external | hardcoded | external | symbol-only,discord-mirror | <:lab:1507982217102753962> |  |
| 273 | external | hardcoded | external | symbol-only,discord-mirror | 📥 |  |
| 274 | external | hardcoded | external | symbol-only,discord-mirror | 📤 |  |
| 275 | external | hardcoded | external | symbol-only,discord-mirror | ➕ |  |
| 276 | external | hardcoded | external | symbol-only,discord-mirror | ➖ |  |
| 277 | external | hardcoded | external | symbol-only,discord-mirror | 🔀 |  |
| 278 | external | hardcoded | external | symbol-only,discord-mirror | 🏁 |  |
| 279 | external | hardcoded | external | symbol-only,discord-mirror | 🏳️ |  |
| 280 | external | hardcoded | external | symbol-only,discord-mirror | 🌎 |  |
| 281 | external | hardcoded | external | symbol-only,discord-mirror | 🥇 |  |
| 282 | external | hardcoded | external | symbol-only,discord-mirror | ⏱️ |  |
| 283 | external | hardcoded | external | symbol-only,discord-mirror | 🚀 |  |
| 284 | external | hardcoded | external | symbol-only,discord-mirror | 💬 |  |
| 307 | external | hardcoded | external | discord-mirror | A team was created |  |
| 308 | external | hardcoded | external | discord-mirror | A team was released |  |
| 309 | external | hardcoded | external | discord-mirror | A player joined a team |  |
| 310 | external | hardcoded | external | discord-mirror | A player left a team |  |
| 311 | external | hardcoded | external | discord-mirror | A team surface was created |  |
| 312 | external | hardcoded | external | discord-mirror | A team set a first-to-produce record |  |
| 313 | external | hardcoded | external | discord-mirror | A team set a production speed record |  |
| 314 | external | hardcoded | external | discord-mirror | A team finished a technology |  |
| 315 | external | hardcoded | external | discord-mirror | A player joined the game (team-aware) |  |
| 316 | external | hardcoded | external | discord-mirror | A player left the game (team-aware) |  |
| 317 | external | hardcoded | external | discord-mirror | A player switched teams mid-game |  |
| 318 | external | hardcoded | external | discord-mirror | A team launched a rocket |  |
| 319 | external | hardcoded | external | discord-mirror | A chat message (global channel only) |  |
| 365 | external | hardcoded | external | concat,sentence-fragments,server-side-st… | player  | "player " .. d.player_index fallback when the player name is unresolved, used as the subject of bridge_text se… |
| 367 | external | hardcoded | external | server-side-string,discord-mirror | %s created %s | string.format(who, team) in bridge_text; who is player name or 'player N' fragment, team is display name |
| 368 | external | hardcoded | external | server-side-string,discord-mirror | %s was created | string.format(team) in bridge_text when no player is known |
| 370 | external | hardcoded | external | server-side-string,discord-mirror | %s was released | string.format(team) in bridge_text |
| 372 | external | hardcoded | external | server-side-string,discord-mirror | %s joined %s | string.format(who or "A player", team) in bridge_text |
| 372 | external | hardcoded | external | sentence-fragments,discord-mirror | A player | fallback subject literal used at lines 372 and 374 when who is nil |
| 374 | external | hardcoded | external | server-side-string,discord-mirror | %s left %s | string.format(who or "A player", team) in bridge_text |
| 376 | external | hardcoded | external | server-side-string,discord-mirror | Surface %s was created for %s | string.format(d.surface_name, team) in bridge_text |
| 558 | external | hardcoded | external | concat,sentence-fragments,server-side-st… | player  | "player " .. event.player_index fallback subject in on_player_changed_force bridge presentation |
| 565 | external | hardcoded | external | server-side-string,discord-mirror | %s switched to %s | string.format(who, helpers.team_display(new_name)) for mid-game team switch |
| 578 | external | hardcoded | external | server-side-string,discord-mirror | %s joined %s | string.format(who, helpers.team_display(new_name)) for deliberate team join |
| 587 | external | hardcoded | external | server-side-string,discord-mirror | %s left %s | string.format(who, helpers.team_display(old_name)) for team leave |
| 610 | external | hardcoded | external | concat,sentence-fragments,server-side-st… | %s %s — %s | string.format(player.name, verb, helpers.team_display(fn)); verb is the reusable fragment 'joined the game'/'l… |
| 612 | external | hardcoded | external | concat,sentence-fragments,server-side-st… | %s %s | string.format(player.name, verb) for team-less players |
| 626 | external | hardcoded | external | concat,server-side-string,discord-mirror | <author> [<team>]: <message> | (author_name .. " [" .. team .. "]" or author_name) .. ": " .. message — Discord copy of chat lines |
| 638 | external | hardcoded | external | sentence-fragments,server-side-string,di… | joined the game | verb fragment passed into connection_text |
| 651 | external | hardcoded | external | sentence-fragments,server-side-string,di… | left the game | verb fragment passed into connection_text |

## scripts/space_age.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 47 | log | hardcoded | log-only | concat | [multi-team-support] Space Age detection: active= | .. tostring(cached_active) |

## scripts/spawn_labels.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 59 | other | hardcoded | player | concat,newlines,rich-text,server-side-st… | <team tag [leader]>'s\n<location name> | helpers.team_tag_with_leader(force_name) .. "'s\n" .. location_name — world-rendered text (rendering.draw_text… |
| 65 | other | hardcoded | player | concat,newlines,rich-text,server-side-st… | [img=utility/clock]  | appended as "\n[img=utility/clock] " .. helpers.fmt_duration_coarse(game.tick - start) — birth-clock line on t… |

## scripts/spectator/core.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 22 | chat | hardcoded | player | rich-text,server-side-string | You're spectating: team chat still reaches your team, but other spectators can see it too. | two literals joined with ..; wrapped in helpers.colored_name(text, chat_channel.LOCAL_COLOR) adding [color=] t… |
| 84 | chat | hardcoded | player | sentence-fragments,server-side-string | is now spectating | picked via `is_entering and ... or ...` and spliced into the announce broadcast |
| 84 | chat | hardcoded | player | sentence-fragments,server-side-string | stopped spectating | picked via `is_entering and ... or ...` and spliced into the announce broadcast |
| 90 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… |  (<surface name>) | " (" .. helpers.display_surface_name(surface.name) .. ")" suffix fragment |
| 101 | chat | hardcoded | player | concat,sentence-fragments,rich-text,serv… | <viewer> is now spectating\|stopped spectating <target player> (<team tag>) (<surface>) | colored_name(viewer) .. " " .. action .. " " .. target_text; target_text is colored player name + " (" .. colo… |
| 104 | log | hardcoded | log-only | concat | [multi-team-support:spectator] <viewer> <action> <surface> / <player> / <team> | concat of viewer.name, action fragment, optional surface.name, optional target_player.name, target_name |
| 167 | log | hardcoded | log-only |  | [multi-team-support:spectator] init: starting |  |
| 171 | log | hardcoded | log-only |  | [multi-team-support:spectator] init: created spectator force |  |
| 202 | log | hardcoded | log-only |  | [multi-team-support:spectator] init: complete, permission group configured |  |
| 220 | log | hardcoded | log-only | concat | [multi-team-support:spectator] setup_force:  | .. new_force.name |

## scripts/spectator/events.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 19 | chat | hardcoded | player |  | [multi-team-support] You are now viewing as a friend. Crafting resumed. |  |
| 21 | chat | hardcoded | player |  | [multi-team-support] You are now viewing as a friend. |  |
| 23 | log | hardcoded | log-only | concat | [multi-team-support:spectator] upgraded <player> from spectator to friend-view | concat with p.name |
| 27 | log | hardcoded | log-only | concat | [multi-team-support:spectator] downgrading <player> from friend-view to spectator (unfriended) | concat with p.name |
| 35 | chat | hardcoded | player | concat,server-side-string | [multi-team-support] <team> unfriended you. Now spectating (crafting paused). | "[multi-team-support] " .. helpers.display_name(player_force.name) .. " unfriended you. Now spectating (crafti… |
| 38 | chat | hardcoded | player | concat,server-side-string | [multi-team-support] <team> unfriended you. Now spectating. | same concat as line 35 without the crafting clause; Lua picks between the two based on crafting queue |
| 79 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_controller_changed: <player> exited remote view, restoring fo… | concat with player.name |
| 136 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_player_changed_surface: <player> camera left target force ter… | concat of player.name, target_force_name, (owner or "<unowned>"), player.surface.name |
| 146 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_friend_changed: <force> friended \| unfriended <force> | concat; " friended "/" unfriended " chosen by is_friend |
| 172 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_player_left: restoring <player> | concat with player.name |
| 187 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_player_joined: restored <player> from spectator force | concat with player.name |
| 190 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_player_joined: cleaned stale storage for <player> | concat with player.name |
| 204 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_player_joined: fixed leftover spectator permission group for … | concat with player.name |
| 208 | log | hardcoded | log-only | concat | [multi-team-support:spectator] on_player_joined: reset negative crafting modifier for <player> | concat with player.name |
| 222 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… | [on <team>'s base][spectator]  | "[on " .. helpers.display_name(target_fn) .. "'s base][spectator] " — chat prefix prepended to the player's ch… |
| 225 | chat | hardcoded | player | concat,sentence-fragments,server-side-st… | [on <team>'s base][friend]  | "[on " .. helpers.display_name(owner) .. "'s base][friend] " — chat prefix prepended to the player's chat line… |

## scripts/spectator/ops.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 11 | log | hardcoded | log-only | concat | [multi-team-support:spectator] enter: <player> → <force> on <surface> at <pos> | concat with player.name, target_force.name, surface.name, serpent.line(position) |
| 33 | log | hardcoded | debug |  | spectator.enter: BEFORE state changes | passed to helpers.diag (debug diagnostic channel) |
| 36 | log | hardcoded | debug |  | spectator.enter: AFTER apply_spectator_state | helpers.diag |
| 38 | log | hardcoded | debug |  | spectator.enter: AFTER open_remote_view | helpers.diag |
| 42 | log | hardcoded | log-only | concat | [multi-team-support:spectator] enter: done, force= | .. player.force.name |
| 47 | log | hardcoded | log-only | concat | [multi-team-support:spectator] exit:  | .. player.name |
| 48 | log | hardcoded | debug |  | spectator.exit: BEFORE restore_player_state | helpers.diag |
| 53 | log | hardcoded | debug |  | spectator.exit: AFTER restore_player_state | helpers.diag |
| 79 | log | hardcoded | debug | concat | spectator.exit: TELEPORT → <surface> at (x,y) | concat with target_surface.name and string.format("(%.1f,%.1f)", pos.x, pos.y); helpers.diag |
| 151 | log | hardcoded | log-only | concat | [multi-team-support:spectator] exit: done, force= | .. player.force.name |
| 175 | log | hardcoded | log-only | concat | [multi-team-support:spectator] switch_target: <player> → <force> on <surface> | concat |
| 191 | log | hardcoded | log-only | concat | [multi-team-support:spectator] enter_from_remote: <player> → <force> on <surface> at <pos> | concat with serpent.line(position) |
| 221 | log | hardcoded | log-only | concat | [multi-team-support:spectator] enter_from_remote: done, force= | .. player.force.name |
| 228 | log | hardcoded | log-only | concat | [multi-team-support:spectator] enter_friend_view: <player> on <surface> | concat |

## scripts/surface_utils.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 259 | log | hardcoded | log-only |  | [multi-team-support:spectator] cleanup_charts: cleared inactive surface charts |  |

## scripts/team_modifiers.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 42 | gui | hardcoded | player | sentence-fragments | Peaceful biters |  |
| 43 | gui | hardcoded | player | sentence-fragments | peaceful |  |
| 44 | gui | hardcoded | player | rich-text,symbol-only | [img=entity/small-biter] |  |
| 45 | tooltip | hardcoded | player | sentence-fragments | Biters on this team's surfaces never attack first (they still defend themselves). | two literals joined with .. at load time (static result); reused in card_line tooltips |
| 95 | chat | hardcoded | player | sentence-fragments | See the Teams panel or /mts-modifiers for every team's settings. | guidance() helper — appended to the M.set broadcast, the hud_tag tooltip, and print_mode_notice |
| 128 | chat | hardcoded | player | sentence-fragments | Admin | fallback subject when no admin_player is passed to M.set |
| 129 | chat | hardcoded | player | concat,sentence-fragments,rich-text,serv… | [Admin] <admin> enabled\| disabled <modifier label> for <team tag [leader]> (non-competitive mo… | "[Admin] " .. colored_name(admin) .. (enabled and " enabled " or " disabled ") .. def.label .. " for " .. team… |
| 134 | chat | hardcoded | player | sentence-fragments,concat |  This team is now marked non-competitive until it disbands. | conditionally appended to the M.set broadcast when newly marked |
| 158 | chat | hardcoded | admin | concat,plural,rich-text,sentence-fragmen… | Cannot return to competitive mode: <team tags> have\|has played with team modifiers and are\|is… | "Cannot return to competitive mode: " .. table.concat(team_tag_with_leader list, ", ") .. (plural and " have" … |
| 183 | chat | hardcoded | player |  | All team modifiers removed — every team is back on standard settings. |  |
| 209 | gui | hardcoded | player | concat,sentence-fragments | <modifier labels joined by ', '> | table.concat(labels, ", ") in M.describe — one-line modifier summary reused by hud_tag |
| 217 | gui | hardcoded | player | concat,sentence-fragments | non-competitive | HUD caption; appends " · " .. table.concat(shorts, " · ") when the team has modifiers |
| 225 | gui | hardcoded | player | sentence-fragments | standard settings | fallback for M.describe in the hud_tag tooltip |
| 227 | tooltip | hardcoded | player | concat,newlines,sentence-fragments | This server allows per-team modifiers.\nThis team: <modifiers\|standard settings>\n<guidance> | "This server allows per-team modifiers.\nThis team: " .. mine .. "\n" .. guidance() |
| 244 | gui | hardcoded | player | concat,rich-text | <icon> <label> (joined by three spaces) | caps[i] = def.icon .. " " .. def.label; table.concat(caps, "   ") — Teams GUI card line |
| 245 | tooltip | hardcoded | player | concat,newlines | <modifier tooltips joined by \n>\n(non-competitive team modifier) | table.concat(tips, "\n") .. "\n(non-competitive team modifier)" |
| 252 | gui | hardcoded | player | rich-text | [color=1,0.65,0][non-competitive][/color] |  |
| 258 | chat | hardcoded | player | sentence-fragments | [Records \| non-competitive] | prefix fragment prepended to record/milestone broadcasts (tech_records, milestones) |
| 258 | chat | hardcoded | player | sentence-fragments | [Records] | prefix fragment prepended to record/milestone broadcasts when non-competitive mode is off |
| 264 | chat | hardcoded | player | concat,rich-text,sentence-fragments,serv… | [color=1,0.65,0]This server is running in NON-COMPETITIVE mode — teams may play under different… | literal .. guidance() .. "[/color]" — player.print on join |

## scripts/team_rename.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 34 | chat | hardcoded | player | sentence-fragments | You are not on a team yet. | returned as err; printed by both the /mts-rename command and the Team Settings GUI |
| 37 | chat | hardcoded | player | sentence-fragments | Only the team leader can rename the team. | returned as err; printed by callers |
| 41 | chat | hardcoded | player | sentence-fragments | Team name cannot be empty. | returned as err; printed by callers |
| 45 | chat | hardcoded | player | concat,plural,sentence-fragments | Team name is too long (max <N> characters). | "Team name is too long (max " .. max_len .. " characters)." — number interpolated by concat |
| 55 | chat | hardcoded | player | sentence-fragments | Another team already uses that name. | returned as err; printed by callers |
| 60 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <player> renamed their team to <team tag [leader]>. | "[Team] " .. colored_name(player) .. " renamed their team to " .. team_tag_with_leader .. "." — helpers.broadc… |

## scripts/team_slots.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 145 | log | hardcoded | log-only | concat | [multi-team-support] WARNING: Could not create <force> (64 force limit reached) | concat with force_name |
| 164 | other | hardcoded | player | server-side-string | Team %02d | string.format("Team %02d", i) — default team display name baked into storage.team_names at pool creation; show… |
| 165 | log | hardcoded | log-only | concat | [multi-team-support] created team slot:  | .. force_name |
| 181 | chat | hardcoded | player | concat,plural | No team slots available. All <N> teams are occupied. | "No team slots available. All " .. max_teams() .. " teams are occupied." — number by concat |
| 214 | log | hardcoded | log-only | concat | [multi-team-support] team clock started for <force> at tick <tick> | concat with force_name and game.tick |
| 221 | log | hardcoded | log-only | concat | [multi-team-support] <player> claimed slot <N> (<force>) | concat with player.name, slot, force_name |
| 244 | other | hardcoded | player | server-side-string | Team %02d | string.format("Team %02d", slot) — resets the display name on slot wipe/release |
| 271 | chat | hardcoded | player |  | The team you requested to join is no longer available. |  |
| 315 | log | hardcoded | log-only | concat | [multi-team-support] released team slot:  | .. force_name |
| 434 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <team tag [leader]> has been disbanded. | "[Team] " .. team_tag .. " has been disbanded." plus conditional appended sentence; helpers.broadcast |
| 435 | chat | hardcoded | player | sentence-fragments,concat |  Their base has been cleaned up. | appended to the disband broadcast when surfaces were deleted |
| 440 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <player> has left <team tag [leader]>. | "[Team] " .. colored_name(player) .. " has left " .. team_tag .. "." — helpers.broadcast |
| 451 | chat | hardcoded | player | concat,rich-text,server-side-string | <new leader> is now the leader of <team tag [leader]>. | cn_leader .. " is now the leader of " .. team_tag .. "." — member.print to each connected team member |
| 454 | chat | hardcoded | player | concat,rich-text,server-side-string | [Team] <new leader> now leads <team tag [leader]>. | "[Team] " .. cn_leader .. " now leads " .. team_tag .. "." — helpers.broadcast |

## scripts/tech_records.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 63 | chat | hardcoded | player | concat,rich-text,sentence-fragments,serv… | %s %s was the first to research %s! | string.format(team_modifiers.records_tag(), helpers.team_tag(force), helpers.tech_rich_name(tech)) — helpers.b… |
| 66 | flying-text | hardcoded | player | concat,newlines,rich-text,server-side-st… | First!\n[technology=<tech>] | "First!\n[technology=" .. tech.name .. "]" — pop_text.milestone animated pop-up above team members |
| 71 | chat | hardcoded | player | concat,rich-text,sentence-fragments,serv… | %s %s is fastest to research %s in %s (previous record: %s in %s) | string.format(records_tag, team_tag, tech_tag, format_elapsed(new elapsed), team_tag(prev.team), format_elapse… |
| 79 | flying-text | hardcoded | player | concat,newlines,rich-text,server-side-st… | New record!\n[technology=<tech>] | "New record!\n[technology=" .. tech.name .. "]" — pop_text.milestone |

## settings.lua

| line | cat | status | vis | hazards | text | assembly |
|---|---|---|---|---|---|---|
| 11 | setting | localised | player |  | mod-setting-name.mts_max_teams / mod-setting-description.mts_max_teams |  |
| 34 | setting | localised | player |  | mod-setting-name.mts_passive_radars / mod-setting-description.mts_passive_radars |  |
| 41 | setting | localised | player |  | mod-setting-name.mts_discord_url |  |
| 43 | setting | hardcoded | player |  | https://discord.gg/tWz4FT74pH | default_value of mts_discord_url; the runtime value is interpolated into player-facing chat broadcasts (events… |
| 52 | setting | localised | player |  | mod-setting-name.mts_claust_oil_distance_tiles / mod-setting-description.mts_claust_oil_distanc… |  |

## Structural notes from the sweep (per area)

### gui/ (admin, awards, buddy, chat_switch, confirm, follow_cam, friendship, hud_clock, landing_pen)

Structural findings for the localisation plan. (1) Central message pipeline: nearly every chat string flows through scripts/helpers.lua — broadcast(), team_tag(), team_tag_with_leader(), force_tag(), colored_name(), display_name(), fmt_duration(), format_elapsed(), diag(), add_title_bar(title) — all of which take/return plain Lua strings. Every broadcast is therefore assembled server-side into one English string (server-side-string hazard is pipeline-wide); converting these helpers to accept/emit LocalisedStrings is the prerequisite for everything else. helpers.add_title_bar(frame, title) is the shared title-bar builder (admin.lua:45, buddy_requests.lua:45, confirm.lua:51, follow_cam_frame.lua:99). (2) Data-driven GUI text defined outside the scanned set but rendered here: admin_flags.FLAGS def.label/def.tooltip (admin.lua:78,80) and team_modifiers.MODIFIERS def.label/def.tooltip (admin.lua:125,145) live in scripts/admin_flags.lua and scripts/team_modifiers.lua; team_modifiers.marked_badge/hud_tag and chat channel badge text come from scripts/team_modifiers.lua and scripts/chat_tag.lua; admin_flags.announce_starter_items_added builds the starter-item broadcast (admin.lua:349,378,424); friendship.get_state's returned label/tooltip strings are rendered by surfaces_gui.lua; confirm.lua receives title/message/confirm_text/cancel_text as plain strings from callers (see usage doc: "Leave Team?", "Are you sure you want to leave?\nYour items will be dropped as a corpse.") — those call sites need separate inventory. clock_caption returns (hud_clock.lua) are reused by gui/team_card.lua. (3) Repeated conventions worth shared locale keys: "[Team] " and "[Admin] " broadcast prefixes; "Clear search"; "Close"; team-tag + two-space + value column formatting. (4) Hazard hotspots: awards search filters on internal prototype names, not localised names (awards.lua:178/201 and the tooltip at 467 promises internal-name matching) — after localisation players will search display names and miss; ordinals "1st/2nd/3rd" and "%d / %d match"/"%d ×" need plural/ordinal-aware keys; admin starter-item rows display internal item.name instead of localised_name (admin.lua:199,203,204,213); leading two-space indents used as layout ("  (no teams yet)", follow_cam_frame.lua:168) are fragile; fixed pixel widths (Body/View button 46px, count field 60px, name label minimal_width 160) may clip longer translations. (5) rendering.draw_text ground text (landing_pen_terrain.lua) is a single world render shared by all players — it can take a LocalisedString in 2.0 but will still be one language for everyone. (6) Numeric-only display strings not reported as entries: tostring(i) dropdown items for the buddy team limit (admin.lua:97) and the "1" default already listed. (7) helpers.diag messages classified as debug diagnostics (category log, visibility debug); the two log() calls in admin.lua are log-only. (8) The workspace contains an open-discord-bridge project; if that bridge mirrors in-game chat, every helpers.broadcast string would additionally carry the discord-mirror hazard — not verifiable from these files. (9) gui/follow_cam.lua and gui/landing_pen.lua contain no GUI literals of their own (follow_cam.lua: zero strings; landing_pen.lua only the two diag messages) — both are handler/facade modules.

### gui/ (lfm_hint … start_playing_gui)

Files with zero display strings: gui/nav.lua, gui/pen_ops.lua, gui/platform_hub.lua. Structural findings for the localisation plan: (1) nav.lua persists top-bar button specs INCLUDING the tooltip string into storage.nav_button_order and replays them via nav.rebuild_buttons — plain-English tooltips (e.g. research.lua:172 "Research Comparison") get frozen into save files; migrating to LocalisedString tooltips needs a storage migration and a check that a LocalisedString survives the storage round-trip. (2) helpers.add_title_bar(frame, title) is a shared pipeline taking a plain string title ("Landing Pen", "Ready to Start?", and the concatenated "Research: You vs X"); converting its signature to accept LocalisedString covers several call sites at once. (3) helpers.fmt_duration is the shared tick-to-time formatter used by research_diff/research_overview; its output is always embedded mid-sentence via '..' ("X playing", "Researched: X after spawn", "You started X earlier than ..."), so every consumer needs parameterised locale keys. (4) helpers.display_name/helpers.team_tag inject team/player names mid-sentence throughout pen_gui and research files — classic word-order hazard; team_tag likely contains rich-text. (5) research_diff tooltips already use LocalisedString {"", localised_label, hardcoded_suffix} form (status partial) — easiest migration, just replace the hardcoded tails with keyed parameters. (6) Repeated pattern of English variants chosen in Lua and/or expressions: pen_gui spawn-button 3-way tooltip (lines 171-175), leader "— offline" suffix, research_diff 3-way clock context, queue "Currently researching"/"Queued at position N", overview "Collapse"/"Expand all N technologies" — each variant must become its own locale key. (7) diff_section (research_diff.lua:216-217) appends "  (N)" to every passed section title — count formatting should move into the keys. (8) pen_info_panel writes display_panel_text, an API that accepts only a plain string shown identically to all players (and on the map); the default text plus admin-authored run descriptions cannot be per-player localised — document as a known limitation. (9) platform_hub frame captions come from other mods via remote_api.register_platform_hub_widget def.caption — pass-through, consumers own localisation. (10) start_playing_gui.lua:38 uses English possessive ("{team}'s clock") and hardcodes the "(press M)" keybind instead of a control-input locale reference. (11) research_diff.lua:257 sorts the infinite-tech table by internal prototype name while displaying localised labels — display order will look unsorted in other languages; research_overview.get_player_forces tie-breaks section order on the display name string. (12) helpers.diag (return_button.lua:75) is a debug message pipeline building plain strings; fine to leave unlocalised but worth a policy decision. Several helpers-owned strings (add_title_bar close button, add_show_offline_checkbox caption, team_tag, diag) live in scripts/helpers.lua, outside this file set — scan it next.

### gui/stats/*, team_card, teams_data, team_settings, teams, welcome

Coverage: gui/stats/discovery.lua, gui/stats/handlers.lua, and gui/stats/quality.lua contain zero display strings (pure data/routing). No locale references exist anywhere in these 13 files except prototype localised_name passthroughs (gui/stats/grid.lua:84 tooltip, gui/stats/panel.lua:162) — everything else is hardcoded English.

Shared message pipelines (central localisation targets): (1) teams_data.fmt_ago / fmt_playtime / activity_info produce English fragments ("active", "just now", "<d>d ago", "<h>h <m>m", "< 1m", "online now", "last seen: ...", "never seen") that are embedded via concatenation into captions and tooltips in team_card.lua (lines 54, 271), stats grid.lua (line 175), and build_activity_tooltip — one locale-aware time formatter fixes all consumers. (2) counts.fmt hardcodes decimal point and k/M suffixes for every stats cell and quality-breakdown tooltip. (3) The selected-tab pattern '"> " .. label' repeats three times in panel.lua (categories line 115, time periods line 129, quality line 148); a single "selected" template key covers all. (4) The "Team slot N (force-name)" tooltip and "#N" slot caption are duplicated between grid.lua (158-159) and team_card.lua (42-43).

Out-of-scope modules whose display strings these files consume (need their own scan): scripts/helpers.lua (display_name, team_tag, team_tag_with_leader — rich-text team tags; add_title_bar; add_show_offline_checkbox — the checkbox caption literal lives there; broadcast — check whether it mirrors to the Discord bridge: if so the two LFM broadcasts in team_settings.lua:326/329 gain 'discord-mirror'), gui/friendship.lua (get_state returns label text + tooltip rendered in team_card.lua:145-157), gui/hud_clock.lua (clock_caption rendered at team_card.lua:70-77 and refreshed at 324), scripts/team_modifiers.lua (card_line at team_card.lua:82-89, MODE_COLOR), gui/research_diff.lua (queue_tooltip at team_card.lua:367), scripts/team_rename (rename error strings printed via player.print(err) at gui/team_settings.lua:289-290). Remote-registered tab captions (def.caption at team_settings.lua:188-195 and welcome.lua:227-243) come from other mods — the mts-v1 remote contract should accept LocalisedString captions.

Hazards worth planning around: team lists are sorted by display string (counts.player_forces sorts on helpers.display_name output at counts.lua:257; grid.lua:142 tie-breaks on player_name) — 'sorted-by-text' once names localise. team_settings' 16-char name cap and its "n / 16" counter use Lua # (byte length) and :sub truncation (lines 348-350), which splits multibyte UTF-8 characters. Planet/surface display names are Lua-capitalised internal names ("<Planet> base", teams_data.lua:42/77) instead of prototype localised names; "in transit" and space_location internal names likewise bypass localisation. welcome.lua's About tab is an entire documentation page of literal-concatenated paragraphs that textually duplicates nav-button titles, panel names, and button captions ("Start recruiting" is also quoted inside team_settings.lua:131) — these cross-references must stay consistent in translation. Tab captions "  About  "/"  Discord  " use padding spaces for width. Empty-string captions used as spacers (grid.lua:64/126/197, team_card.lua:97 non-leader branch) were not reported.

### scripts/ (admin_flags … debug) + commands/

Zero localisation exists in these 12 files: not one {"key"} LocalisedString; every display string is a plain Lua string, so all statuses are 'hardcoded'. Files with no user-visible strings: scripts/blueprint_lock.lua (permission-group manipulation only; "Default" is an engine group identifier), scripts/buddy_store.lua (storage/frame management; frame names are identifiers), scripts/commands.lua (pure facade). Structural points for the localisation plan: (1) Message pipeline helpers live in scripts/helpers.lua (outside this scan) and appear everywhere: helpers.broadcast (server-wide print of a prebuilt string), helpers.colored_name (wraps a name in [color=] rich text), helpers.item_rich_name ([item=] tags), helpers.team_tag / team_tag_with_leader (team labels embedded mid-sentence). Because sentences are assembled around these helper outputs with .., nearly every dynamic message carries concat + rich-text + server-side-string hazards; converting to LocalisedStrings means these helpers must return fragments usable as __1__-style parameters. (2) chunk_trim.notify(caller_idx, msg) delivers to the caller OR broadcasts via game.print if the caller disconnected — trim results are marked visibility 'player' for that reason; chunk_trim.start also returns English error strings as return values (string|nil contract) that commands/admin.lua prints, so localising changes that API contract. (3) The confirm-dialog pipeline (gui/confirm.lua, outside scan) receives title/message/confirm_text/cancel_text as plain strings from both commands/admin.lua and commands/team.lua; it must accept LocalisedString for any of those to localise. Bullet-list confirm messages hardcode \n layout, manual line-wrapping, and one Lua plural pick (count == 1 and "" or "s"). (4) The guard string "This command can only be used by a player." repeats verbatim 10 times across admin.lua/debug_cmd.lua/team.lua (all via game.print, i.e. broadcast when run from server console/RCON); "Team '<x>' does not exist." repeats 4 times; "Usage: ..." lines repeat per command — obvious shared-locale-key candidates. (5) Cross-file consistency constraints: chat_channel.lua announce words TEAM-ONLY/GLOBAL, chat_tag.lua badge words TEAM/GLOBAL (sharing chat_channel's color constants), and the admin-flag tooltip at admin_flags.lua:53 which references "[GLOBAL]/[TEAM]" must all be translated in sync; the staged-start tooltip (admin_flags.lua:63) quotes the "Start Playing" button caption defined elsewhere. (6) player.tag (chat_tag.lua) is a plain string field — it can NEVER carry a LocalisedString, so the badge words will remain one server-chosen language; same for anything routed through helpers.broadcast as prebuilt strings unless converted. (7) The debug task label (debug.lua:55) and detail are English strings persisted in storage at schedule time and replayed later by /mts-debug list — persisted display strings won't retranslate. (8) commands.add_command name and help both accept LocalisedString in Factorio 2.0, so the 13 help texts are directly localisable; the command NAMES themselves (mts-disband, t, etc.) are also the literal tokens players type and are conventionally left untranslated. (9) Plural handling is ad hoc throughout: "(s)" suffixes (surface(s), task(s), player(s), action(s), force(s)), Lua ternary plural picks (admin.lua:140, team.lua:165-167), and an always-plural "item types" in a log line — these need {"...", n} plural-aware locale keys. (10) Fragments built in files outside this scan surface here: teams_data.activity_info().ago_text (admin.lua:132), team_modifiers.describe/marked_badge (team.lua:201-205), team_rename.attempt error strings (team.lua:141), surface_info.gps/location (team.lua:97-98) — the inventory of those source files must cover them.

### scripts/ (force_utils … records) + pause/

Structural findings for the localisation plan. (1) helpers.lua is the message-fragment factory: team_display ("Team " prefix), team_tag, team_tag_with_leader (dim-bracket leader suffix), force_tag, colored_name, item_rich_name, tech_rich_name all return plain Lua rich-text fragments that callers concatenate into sentences across the whole mod — every announcement built through them is a server-side single-language string. Localising means converting these to LocalisedString builders or locale keys with placeholders. (2) The duration formatters fmt_duration / fmt_duration_coarse / format_elapsed hardcode English h/m/s unit suffixes via string.format and are reused by GUIs and chat in other files; they need locale-aware unit handling once, centrally. (3) global_milestones.announce() is a broadcast pipeline: one pre-built string goes to helpers.broadcast (player.print loop) AND pop_text.global_milestone (rendering.draw_text). Both APIs accept LocalisedString in Factorio 2.0, so the pipeline can carry a LocalisedString — EXCEPT the Discord bridge payload (remote_api.emit_to_bridge text field, line 146) which must stay a plain string; announcements that mirror to Discord need dual-format (LocalisedString for in-game + English plain string for the bridge). (4) pop_text.lua presets are display-agnostic — they render whatever text_str callers pass (use_rich_text=true); the only literal inside is "RIP!". Localisation work for pop text lives at the call sites. (5) helpers.tech_label (line 450) is the one locale-correct pattern in this batch: {"", localised_name, " ", level} composition — a model for the rest. (6) planet_map's logistic-rewrite notify shows raw internal surface variant names (mts-vulcanus-1) instead of display_surface_name — both a cosmetic and a localisation issue. (7) All pause/power and pause/wires diag strings sit behind file-local DIAG=false flags (visibility debug); helpers.diag and the plain log() calls are always-on but log-file only. (8) Files with zero display strings: scripts/pause/control.lua, scripts/pause/state.lua, scripts/pop_text_tick.lua, scripts/records.lua. records.lua sorts by numeric fields only (no sorted-by-text hazard). (9) helpers.player_state's tiny fragments ("?", "nil", "%s@%s", "(%.1f,%.1f)") are folded into the line-108 entry — all log-only.

### scripts/ (remote_api … tech_records) + spectator/

Zero locale references in any of the 15 files — every display string is hardcoded English, so no 'localised'/'partial' entries exist. Structural points for the localisation plan: (1) Message pipeline: nearly all player-facing announcements flow through helpers.broadcast (game.print of a pre-assembled plain Lua string) and helpers.colored_name / helpers.team_tag / helpers.team_tag_with_leader (rich-text [color=] wrappers around team/player names) — helpers.lua was not in the scan set but is the choke point to convert to LocalisedString end-to-end. (2) remote_api.lua's bridge_text/connection_text/emit_chat/bridge_payload build Discord-bound sentences; these MUST remain plain strings (a LocalisedString cannot cross to Discord), so they need a separate single-language path, not locale keys — do not merge them with in-game message localisation. The bridge also receives static event descriptions (register_source) and emoji category labels. (3) team_modifiers.guidance() is a reusable sentence fragment appended to a broadcast, a HUD tooltip, and a join notice; the M.MODIFIERS spec table (label/short/icon/tooltip) is composed at four different sites (admin broadcast, HUD tag, Teams-card caption+tooltip, describe) — the worst sentence-fragment hotspot. (4) disable_blocked_reason hand-rolls English pluralisation (have/has, are/is); team_slots line 181 and team_rename line 45 hardcode plural nouns next to interpolated counts. (5) Default team display name string.format("Team %02d", slot) is baked into storage.team_names at pool creation and re-baked on release — persisted server-side, so it will stay in the server's language unless generation moves to a locale key resolved at display time. (6) spawn_labels.compute_text and the spectator chat prefixes build English possessive ("<name>'s") by concatenation; the spawn label is world-rendered text (rendering.draw_text) which only accepts LocalisedString in 2.0 if passed as such — currently plain. (7) pop_text.milestone strings mix literal text, \n, and [technology=] rich text. (8) team_rename.attempt returns raw English error strings printed by both the /mts-rename command and the Team Settings GUI — single source, easy to key. (9) All log() calls use a "[multi-team-support…]" prefix convention and are log-only; helpers.diag calls (ops.lua) assumed debug-gated (helpers.lua not read — verify). Files with no reportable strings: scripts/spectator.lua (facade), scripts/team_clock.lua, scripts/team_disband.lua, scripts/team_surfaces.lua.

### events/, milestones/, root files

Scope: 16 files read fully; locale/en/locale.cfg was additionally checked to confirm the four setting prototypes are localised via implicit [mod-setting-name]/[mod-setting-description] keys (mts_discord_url has a name entry but no description entry). Zero display strings found in: events/helpers.lua, events/player_force.lua, events/player_removed.lua, milestones/config.lua (categories are identifier keys), data.lua (sprite prototypes have no display names), data-final-fixes.lua (requires only). Structural findings for the localisation plan: (1) helpers.broadcast (scripts/helpers.lua, outside this set) is the single chat pipeline — every broadcast passes a fully-assembled plain Lua string, so one server-language string reaches all players; converting broadcast to accept LocalisedString would fix ~15 call sites at once. (2) Rich-text fragment builders helpers.colored_name, helpers.team_tag, helpers.team_tag_with_leader, helpers.item_rich_name and team_modifiers.records_tag are concatenated into nearly every sentence; they can stay as-is if sentences become parameterised locale keys. (3) The milestone pipeline is the worst hazard cluster: build_achievement_desc / build_external_achievement produce reusable English sentence fragments ("produce their first X", "<verb> <n> <noun>s" with a blind appended-\"s\" plural) that are embedded both in in-game broadcasts AND in Discord payload text (via plain() rich-text stripping) — Discord cannot take a LocalisedString, so localising requires splitting the in-game and bridge texts into separate builders. External consumer milestones receive verb/noun in English via remote call, so that remote interface contract itself blocks full localisation. (4) events/research.lua's Discord text uses the raw tech prototype id, not the localised tech name (intentional for Discord). (5) The "Teams looking for more players" block is copy-pasted twice in player_lifecycle.lua (lines 96-109 and 118-135) — dedupe before localising. (6) helpers.diag is a debug-flag-gated diagnostic pipeline (4 call sites here) — likely exempt from localisation. (7) Strings that reach displays from these files but are DEFINED elsewhere (not reported): team_modifiers.disable_blocked_reason() printed at events/gui_state.lua:143, admin_gui.get_flag_label() flag labels, spectator.get_chat_prefix(), pop_text.rip()'s death text, and remote_api's bridge join/leave messages and BRIDGE_LABELS emoji tags — the gui/*.lua and scripts/*.lua trees need their own scan pass. (8) events/chat.lua's relays rebuild "name: message" per recipient in Lua; the "!"-shout prefix convention and "[spectating] " tag are English-agnostic-ish but the tag itself needs a locale key with per-player print already in place (the loop prints per player, so per-recipient LocalisedStrings are feasible there today).

### compat/, prototypes/

Structural findings for the localisation plan. (1) Message pipeline: helpers.diag (scripts/helpers.lua:126) is the shared diagnostic sink — it wraps log() with a "[multi-team-support:DIAG] " prefix and appends " | " .. helpers.player_state(player); all diag strings in this batch are plain-Lua concatenations and log-only, so they can stay English. (2) compat_utils.planet_display_name (compat/compat_utils.lua:38) fabricates display text by capitalizing the internal planet id ("nauvis" -> "Nauvis") via string ops; it is re-exported by vanilla.lua, voidblock.lua, and mts_dimension_warp.lua, so any consumer that shows its return value produces untranslatable English-mechanism text — should become a {"space-location-name."..planet} lookup at the display site. (3) Repeated composed-LocalisedString pattern {"", {key .. base_name}, hardcoded-suffix} appears in both prototypes/planets.lua (numeric-only suffix, low risk) and prototypes/connections.lua (English " (Team N)" suffix, needs a parameterized key like the passivize-radars one). (4) prototypes/entities/passivize-radars.lua demonstrates the correct pattern: parameterized locale key entity-name.mts-passivized-radar-prefix with the original name as __1__ — copy this for connections.lua. (5) Space platform name player.name .. "'s hub" (platformer.lua:49) is stored as a plain string because platform names cannot be LocalisedStrings — permanently one language for all clients; consider a neutral format like "<name> hub" or locale-free naming. (6) Not reported as strings: surface names ("team-1-nauvis", "mdw-<force>-w0" built at mts_dimension_warp.lua:77, compat_utils.lua:150) are identifiers but can leak into vanilla UI surface lists; spawn_labels.draw(force.name, ...) is invoked from platformer.lua:81 but the visible label text is built in scripts/spawn_labels.lua (outside this batch — make sure another pass covers it, plus scripts/helpers.lua player_state). (7) Files with zero reportable strings: claustorephobic.lua, clone_mirror.lua, deep_core_ops.lua, gridlocked.lua, lignumis.lua (placeholder, comments only), reassign_player_force.lua, remote_safe.lua, space_is_fake.lua, ultracube.lua, vanilla.lua, voidblock.lua, belt_ban.lua, passive-radar.lua (hidden entity, deliberately no localised_name), styles.lua (styles/fonts only). (8) dangoreus.lua reads dangOreus's own settings (easy-mode, floor-is-lava, simple-ore-radius) — no MTS setting prototypes in this batch. (9) The "Cannot build non-miners on resources!" print (dangoreus.lua:153) mirrors upstream dangOreus's message; flagged 'plural' for the hardcoded plural "non-miners"/"resources" phrasing.
