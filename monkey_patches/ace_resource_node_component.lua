local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local HARVEST_ACTION = 'stonehearth:harvest_resource'

local ResourceNodeComponent = require 'stonehearth.components.resource_node.resource_node_component'
local AceResourceNodeComponent = class()

AceResourceNodeComponent._ace_old_set_harvestable_by_harvest_tool = ResourceNodeComponent.set_harvestable_by_harvest_tool
function AceResourceNodeComponent:set_harvestable_by_harvest_tool(harvestable_by_harvest_tool)
   -- if this entity has a renewable component and the json says it's not harvestable by harvest tool,
   -- we don't want to override that
   if harvestable_by_harvest_tool == nil or not self._entity:get_component('stonehearth:renewable_resource_node') then
      self:_ace_old_set_harvestable_by_harvest_tool(harvestable_by_harvest_tool)
   end
end

function AceResourceNodeComponent:_place_reclaimed_items(pile_comp, owner, location)
   local spawned_items, item_count = pile_comp:harvest_once(owner)
   for _, item in pairs(spawned_items) do
      local pt = radiant.terrain.find_placement_point(location, 0, 3)
      radiant.terrain.place_entity(item, pt)
   end

   return spawned_items, item_count
end

-- this is modified only to add the player_id of the harvester to the kill_data of the kill_event
-- and to add item quality for spawned items if this entity is of higher quality
function AceResourceNodeComponent:spawn_resource(harvester_entity, collect_location, owner_player_id)
   local spawned_resources
   local durability_to_consume = 1

   local pile_comp = self._entity:get_component('stonehearth_ace:pile')
   if pile_comp and not pile_comp:is_empty() then
      spawned_resources, durability_to_consume = self:_place_reclaimed_items(pile_comp, harvester_entity, collect_location)
   else
      -- if the pile comp was empty at the start of this, it's because it wasn't initialized properly
      -- so just use normal resource spawning, and don't consider whether the pile is empty for destroying
      if pile_comp then
         durability_to_consume = pile_comp:get_harvest_rate()
         pile_comp = nil
      end
      spawned_resources = {}
      for i = 1, durability_to_consume do
         radiant.append_map(spawned_resources, self:_place_spawned_items(harvester_entity, collect_location))
      end

         -- If we have the vitality town bonus, there's a chance we don't consume durability.
      local town = harvester_entity and stonehearth.town:get_town(radiant.entities.get_player_id(harvester_entity))
      if town then
         local vitality_bonus = town:get_town_bonus('stonehearth:town_bonus:vitality')
         if vitality_bonus then
            local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
            if catalog_data and catalog_data.category == 'plants' then  -- Not log piles.
               local is_wood_resource = false
               for _, item in pairs(spawned_resources) do
                  if radiant.entities.is_material(item, 'wood resource') then
                     is_wood_resource = true
                     break
                  end
               end
               if is_wood_resource then
                  durability_to_consume = vitality_bonus:apply_consumed_wood_durability_bonus(durability_to_consume)
               end
            end
         end
      end

      local quality = radiant.entities.get_item_quality(self._entity)
      if quality > 1 then
         for id, item in pairs(spawned_resources) do
            self:_set_quality(item, quality)
         end
      end
   end

   local player_id = owner_player_id or (harvester_entity and radiant.entities.get_player_id(harvester_entity))
   if harvester_entity then
      for id, item in pairs(spawned_resources) do
         -- add it to the inventory of the owner
         stonehearth.inventory:get_inventory(player_id)
                                 :add_item_if_not_full(item)
      end

      -- Paul: only trigger this once; we don't care about the spawned item, and we don't want exp/buffs being applied multiple times to the shepherd

      --trigger an event on the entity that they've harvested something, and what they're harvesting
      --Note this cannot be async because the entity can be killed
      radiant.events.trigger(harvester_entity, 'stonehearth:gather_resource',
         {harvested_target = self._entity})
   end

   local json = self._json
   if json.resource_spawn_effect then
      local proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'spawn effect effect anchor' })
      local location = radiant.entities.get_world_grid_location(self._entity)
      radiant.terrain.place_entity_at_exact_location(proxy, location)
      local effect = radiant.effects.run_effect(proxy, json.resource_spawn_effect)
      effect:set_finished_cb(function()
         radiant.entities.destroy_entity(proxy)
      end)
   end

   self._sv.durability = self._sv.durability - durability_to_consume

   if self._sv.durability <= 0 or (pile_comp and pile_comp:is_empty()) then
      radiant.entities.kill_entity(self._entity, {source_id = player_id})
   end

   self.__saved_variables:mark_changed()
end

AceResourceNodeComponent._ace_old_request_harvest = ResourceNodeComponent.request_harvest
function AceResourceNodeComponent:request_harvest(player_id, replant)
   local result = self:_ace_old_request_harvest(player_id)

   if result then
      if replant and radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:replant_data') then
         self._entity:remove_component('stonehearth_ace:stump')
         self._entity:add_component('stonehearth_ace:replant')
      else
         self._entity:remove_component('stonehearth_ace:replant')
         self._entity:add_component('stonehearth_ace:stump')
      end
   end

   return result
end

function AceResourceNodeComponent:_set_quality(item, quality)
   item_quality_lib.apply_quality(item, quality)
end

function AceResourceNodeComponent:cancel_harvest_request()
   local task_tracker_component = self._entity:get_component('stonehearth:task_tracker')
   if task_tracker_component and task_tracker_component:is_activity_requested(HARVEST_ACTION) then
      task_tracker_component:cancel_current_task(true)
      return true
   end
end

return AceResourceNodeComponent
