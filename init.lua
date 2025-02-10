minetest.register_chatcommand("vote_kick", {
	privs = { interact = true },
	func = function(name, param)
		if not minetest.get_player_by_name(param) then
			minetest.chat_send_player(name, "There is no player called '" .. 
				param .. "'")
			return
		end

		-- Создаём виртуальный блок голосования (или используем специальную обработку)
		local pos = {x = 0, y = 0, z = 0} -- Фиктивные координаты, можно заменить на реальные
		local meta = minetest.get_meta(pos)

		meta:set_string("owner", name)
		meta:set_string("question", "Kick " .. param .. "?")
		meta:set_string("option1", "Yes")
		meta:set_string("option2", "No")
		meta:set_int("r1", 0)
		meta:set_int("r2", 0)
		meta:set_string("log", "")
		meta:set_int("ready", 1)

		-- Открываем голосование для всех игроков
		for _, player in pairs(minetest.get_connected_players()) do
			vote.showform(pos, player)
		end

		-- Проверка результатов через 60 секунд
		minetest.after(60, function()
			local votes_yes = meta:get_int("r1")
			local votes_no = meta:get_int("r2")
			local total_votes = votes_yes + votes_no

			if total_votes == 0 then
				minetest.chat_send_all("No votes were cast. " .. 
					param .. " remains ingame.")
				return
			end

			local percent_yes = vote.percent(votes_yes, total_votes)
			if percent_yes >= 80 then
				minetest.chat_send_all("Vote passed, " .. 
					votes_yes .. " to " .. 
					votes_no .. ". " .. param .. " will be kicked.")
				minetest.kick_player(param, "The vote to kick you passed.")
			else
				minetest.chat_send_all("Vote failed, " .. 
					votes_yes .. " to " .. 
					votes_no .. ". " .. param .. " remains ingame.")
			end
		end)
	end
})