local modname = minetest.get_current_modname()
local path = minetest.get_modpath(modname)
local S = minetest.get_translator(modname)
--local F = minetest.formspec_escape
local C = minetest.colorize

local string = string
local table = table
local math = math
local sf = string.format

local voting_timeout=10 -- 60
local next_vote_wait_time=300

-- Adds a voting machine
vote={
	user={},
}

vote.percent = function(n, t)
	return math.floor((((n/t)*100)*100)+0.5)/100
end

vote.receive=function(pos, player)
	local pressed={}
	vote.user[player:get_player_name()]=pos
	vote.receive_fields(player,pressed)
	vote.user[player:get_player_name()]=nil
end

-- Получаем выбор игрока и закрываем форму после выбора
vote.receive_fields=function(player, fields)
    -- Если игрок проголосовал, фиксируем его голос
    local pos = vote.user[player:get_player_name()]
    if not pos then return end
    local meta = minetest.get_meta(pos)

    -- Проверяем, что был выбран вариант
    if fields.vote_no then
        meta:set_int("r2", meta:get_int("r2") + 1)  -- Увеличиваем количество голосов "No"
        meta:set_string("log", meta:get_string("log") .. player:get_player_name() .. ", ")
        minetest.close_formspec(player:get_player_name(), "vote.showform")  -- Закрываем форму

        --minetest.log("NO counter=" .. meta:get_int("r2"))
    elseif fields.vote_yes then
        meta:set_int("r1", meta:get_int("r1") + 1)  -- Увеличиваем количество голосов "Yes"
        meta:set_string("log", meta:get_string("log") .. player:get_player_name() .. ", ")
        minetest.close_formspec(player:get_player_name(), "vote.showform")  -- Закрываем форму

        --minetest.log("YES counter=" .. meta:get_int("r1"))
    end
end

minetest.register_on_player_receive_fields(function(player, form, pressed)
	if form == "vote.showform" then
		vote.receive_fields(player, pressed)
		print("Player " .. player:get_player_name() .. " submitted fields " .. dump(pressed))
	end
end)

-- Show form
vote.showform=function(pos, player)
	local meta=minetest.get_meta(pos)
	local gui=""
	local spos=pos.x .. "," .. pos.y .. "," .. pos.z
	local owner=meta:get_string("owner") == player:get_player_name()
	local ready=meta:get_int("ready") == 1
	vote.user[player:get_player_name()]=pos

	if ready then
		-- Используем кнопки для выбора
		gui = "" ..
			"size[8,3]" ..
			"image[3.5,0;1,1;skull.png]" ..  -- Добавляем картинку по центру, масштабируем
			"label[0.1,1.2;" .. meta:get_string("question") .. "]" ..
			"button[0.5,2.3;3,1;vote_yes;" .. meta:get_string("optionYES") .. "]" ..
			"button[4.5,2.3;3,1;vote_no;" .. meta:get_string("optionNO") .. "]"
	else
		gui = "" .. "size[8,3]" .. "label[0,0.2;This voting machine is not ready yet.]"
	end

	-- Отправляем форму игроку
	minetest.after((0.1), function(gui)
		return minetest.show_formspec(player:get_player_name(), "vote.showform", gui)
	end, gui)
end

local last_vote_time = {}

minetest.register_chatcommand("vote_kick", {
	privs = { interact = true },
	func = function(name, param)
		if not param or param == "" then
			minetest.chat_send_player(name, S("Usage: /vote_kick <player_name>"))
			return
		end

		-- Игрок не может голосовать за кик самого себя
		if name == param then
			minetest.chat_send_player(name, S("You cannot start a vote to kick yourself!"))
			return
		end

		local target = minetest.get_player_by_name(param)
		if not target then
			local msg = S("There is no player called @1", param)
			minetest.chat_send_player(name, msg)
			return
		end

		-- Проверяем, запускалось ли голосование недавно
		local current_time = minetest.get_gametime()
		if last_vote_time[name] and current_time - last_vote_time[name] < next_vote_wait_time then
			minetest.chat_send_player(name, S("You must wait before starting another vote."))
			return
		end
		last_vote_time[name] = current_time

		-- Создаём виртуальный блок голосования
		local pos = {x = 0, y = 0, z = 0} -- Фиктивные координаты
		local meta = minetest.get_meta(pos)
		local question = S("`@1` started a vote to kick `@2` from the server.", name, param) .. "\n" .. S("Do you accept?")

		meta:set_string("owner", name)
		meta:set_string("question", question)
		meta:set_string("optionYES", S("Yes"))
		meta:set_string("optionNO", S("No"))
		meta:set_int("r1", 0)
		meta:set_int("r2", 0)
		meta:set_string("log", "")
		meta:set_int("ready", 1)

		-- Открываем форму голосования для всех, КРОМЕ того, кого хотят кикнуть
		for _, player in pairs(minetest.get_connected_players()) do
			local pname = player:get_player_name()
			if pname ~= param then
				vote.showform(pos, player)
			end
		end

		-- Проверка результатов через voting_timeout секунд
		minetest.after(voting_timeout, function()
			-- Время голосования закончилось закрываем формы для всех игроков, кто не успел проголосовать.
			for _, player in pairs(minetest.get_connected_players()) do
				minetest.close_formspec(player:get_player_name(), "vote.showform")
			end

			local votes_yes = meta:get_int("r1")
			local votes_no = meta:get_int("r2")
			local total_votes = votes_yes + votes_no

			if total_votes == 0 then
				local msg = S("Not enough votes collected. @1 remains in the game", param)
				minetest.chat_send_all(msg)
				return
			end

			local percent_yes = vote.percent(votes_yes, total_votes)
			minetest.log(percent_yes)
			if percent_yes >= 80 then
				local msg = S("Voting passed @1 will be kicked out. YES[@2] NO[@3]", param, votes_yes, votes_no)
				minetest.chat_send_all(msg)
				minetest.kick_player(param, S("The vote to kick you passed."))
			else
				local msg = S("Voting failed @1 remains ingame. YES[@2] NO[@3]", param, votes_yes, votes_no)
				minetest.chat_send_all(msg)
			end
		end)
	end
})