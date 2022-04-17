--===================================== Variables ====================================

local loot_claims = {}		-- table of victim npcs who are claimed
local actor_looting_claimed = false
local actor_exploit = false

--==================================== Functions =====================================

local function check_claim(b_id, squad)
	actor_looting_claimed = true
	loot_claims[b_id][3] = loot_claims[b_id][3] + 1			-- count number of times the actor attempts to loot
	local sender
	local faction = squad:get_squad_community()
	for guy in squad:squad_members() do
		local person = guy.object or guy.id and alife():object(guy.id)
		if person and person:alive() then
			sender = person
			break
		elseif guy then
			sender = guy
			break
		end
	end
	-- warned when about to turn hostile
	if (loot_claims[b_id][3] == 3) then
		local sender_header = strformat("%s, %s", sender:character_name(), game.translate_string("st_dyn_news_comm_" .. faction .. "_" .. 6))
		local rnd_last = round_idp(math.random()*4)+1
		local msg = game.translate_string("st_npc_loot_claim_last_"..rnd_last)
		dynamic_news_helper.send_tip( msg, sender_header, 0, 10, sender:character_icon(), "danger", "npc" )
	-- actor trying to steal will be fired upon
	elseif loot_claims[b_id][3] > 3 then
		actor_looting_claimed = false
		if not (game_relations.get_squad_relation_to_actor_by_id(squad.id) == "enemy") then
			for guy in squad:squad_members() do
				local person = guy.object or guy.id and alife():object(guy.id)
				if person and person:alive() then
					person:force_set_goodwill(-3000, db.actor)
				end
			end
			
			local sender_header = strformat("%s, %s", sender:character_name(), game.translate_string("st_dyn_news_comm_" .. faction .. "_" .. 6))
			local rnd_attack = round_idp(math.random()*4)+1
			local msg = game.translate_string("st_npc_loot_claim_attack_"..rnd_attack)
			dynamic_news_helper.send_tip( msg, sender_header, 0, 10, sender:character_icon(), "danger", "npc" )
			game_statistics.increment_reputation(-75)									-- reduce reputation for being a looter/thief							
			xr_effects.inc_faction_goodwill_to_actor(db.actor, nil, { faction, -10 })	-- reduce goodwill with that faction for stealing from them
			loot_claims[b_id] = nil													-- no more claims are made on the body once the actor has decided to steal
		end
		return	-- don't close a hud if it exists
	-- otherwise will be warned first
	else
		local sender_header = strformat("%s, %s", sender:character_name(), game.translate_string("st_dyn_news_comm_" .. faction .. "_" .. 6))
		local rnd_warn = round_idp(math.random()*5)+1
		local msg = game.translate_string("st_npc_loot_claim_warn_"..rnd_warn)
		dynamic_news_helper.send_tip( msg, sender_header, 0, 10, sender:character_icon(), "beep_1", "npc" )
	end
end


-- function to determine if actor is attempting to loot an owned body
local function actor_looting(npc)
	if npc and npc:alive() then
		actor_looting_claimed = false
		return 
	end
	local b_id = npc:id()
	local loot_check = true	
	if not b_id then
		actor_looting_claimed = false
		return
	end
	if not loot_claims[b_id] then
		actor_looting_claimed = false
		return		-- body was actor's kill
	end	
	-- if victim's squadmates/killers are still alive, they claim the body
	local v_squad = loot_claims[b_id][1] and alife_object(loot_claims[b_id][1])
	local k_squad = loot_claims[b_id][2] and alife_object(loot_claims[b_id][2])
	local k_faction = k_squad and k_squad:get_squad_community()
	if v_squad and (v_squad:npc_count() > 0) and not ((game_relations.get_squad_relation_to_actor_by_id(v_squad.id) == "enemy") or v_faction == "zombied") then
		check_claim(b_id, v_squad)
	elseif k_squad and (k_squad:npc_count() > 0) and not ((game_relations.get_squad_relation_to_actor_by_id(k_squad.id) == "enemy") or k_faction == "zombied") then
		check_claim(b_id, k_squad)
	else
		loot_claims[b_id] = {}		-- reset invalid claims
		
		-- previous claim squads are dead - check for nearby allies
		for name,smart in pairs( SIMBOARD.smarts_by_names ) do
			if simulation_objects.is_on_the_same_level(alife():actor(), smart) then
				local smrt = SIMBOARD.smarts[smart.id]
				if (smrt) then
					for k,v in pairs( smrt.squads ) do
						local squad = alife_object(k)
						if squad and not axr_companions.companion_squads[squad.id] then
							local faction = squad:get_squad_community()
							local v_faction = character_community(npc)
							-- body will be claimed by victim allies or killer allies
							if ((faction == v_faction) or (faction == k_faction)) and not ((game_relations.get_squad_relation_to_actor_by_id(squad.id) == "enemy") or faction == "zombied") then
								local dist = squad.position:distance_to(db.actor:position())
								if (dist < 50) then
									local v_claim, k_claim
									if (faction == v_faction) then
										v_claim = squad.id
										loot_claims[b_id][1] = v_claim
									elseif (faction == k_faction) then
										k_claim = squad.id
										loot_claims[b_id][2] = k_claim
									end
									loot_claims[b_id][3] = 0
								end
							end
						end
					end
				end
			end
		end
		v_squad = loot_claims[b_id][1] and alife_object(loot_claims[b_id][1])
		k_squad = loot_claims[b_id][2] and alife_object(loot_claims[b_id][2])
		if v_squad then
			check_claim(b_id, v_squad)
		elseif k_squad then
			check_claim(b_id, k_squad)
		end
	end
end


--==================================== Callbacks =====================================

-- function adds claims and force-closes loot window if corpse is claimed or exploit detected
local function actor_loot_attempt(hud_name)
	local npc = mob_trade.GetTalkingNpc()
    local is_trader = npc and trade_manager.get_trade_profile(npc:id(), "cfg_ltx")
	-- if UI Inventory is corpse
	if (actor_menu.get_last_mode() == 4) then
		local id = ui_inventory.GUI.npc_id
		local npc = db.storage[id] and db.storage[id].object or level.object_by_id(id)
		actor_looting(npc) --Npc checking and corpse claiming
	end
	-- only force-close trade window if actor attempting exploit
	if is_trader and actor_exploit and actor_menu.get_last_mode() == 2 then
		DestroyAll_UI()
		actor_exploit = false
	end
	-- only force-close player inventory UI if glitch fires
	if actor_exploit and actor_menu.get_last_mode() == 1 then
		DestroyAll_UI()
		actor_exploit = false
	end
	-- only force-close if actor is being warned or attacked
	if actor_looting_claimed and (actor_menu.get_last_mode() == 4) then
		hide_hud_inventory()
		actor_exploit = true
	else
		actor_looting_claimed = false
	end
end

-- function to determine initial claims by killers
local function npc_on_death_callback( victim, killer )
	local v_id = victim and victim:id()
	local k_id = killer and killer:id()
	local k_faction = killer and character_community(killer)

	-- mutant attacks do not generate claims
	if not IsStalker(victim) then
		return
	end

	-- victim's loot is unclaimed
	if not loot_claims[v_id] then
		loot_claims[v_id] = {}		-- 1st entry is victim ally claims, 2nd entry is killer ally claims, 3rd entry is number of attempted loots by actor
		-- the body is first claimed by the killer squad
		local k_squad, k_sq_id
		
		if k_id then
			if (k_id == AC_ID) then
				loot_claims[v_id] = nil
				--printf("actor killed target")
				return		-- if actor kills the target, no npcs claim the loot
			else
				k_squad = get_object_squad(killer)
			end
		end

		if k_squad then
			k_sq_id = k_squad.id
		end
		-- temporarily allow anyone (except companions) to make kill claims
		if k_sq_id and not axr_companions.companion_squads[k_sq_id] then
			loot_claims[v_id][2] = k_sq_id		-- killer's squad claims loot
			loot_claims[v_id][3] = 0
		end
	end
end

function on_game_start()
	RegisterScriptCallback("npc_on_death_callback",npc_on_death_callback)
	RegisterScriptCallback("GUI_on_show",actor_loot_attempt)
end
