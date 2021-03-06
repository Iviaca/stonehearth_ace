local rng = _radiant.math.get_default_rng()

local CropComponent = require 'stonehearth.components.crop.crop_component'
local AceCropComponent = class()

AceCropComponent._ace_old_activate = CropComponent.activate
function AceCropComponent:activate()
   self:_ace_old_activate()
   
   local json = radiant.entities.get_json(self) or {}
   self._megacrop_description = json.megacrop_description or stonehearth.constants.farming.default_megacrop_description
   self._megacrop_model_variant = json.megacrop_model_variant

   if not self._sv.megacrop_chance then
      self._sv.megacrop_chance = json.megacrop_chance or stonehearth.constants.farming.BASE_MEGACROP_CHANCE
   end
end

function AceCropComponent:set_fertilized()
   -- not really used at the moment, maybe refactor the fertilize ai to do more of it in here
end

function AceCropComponent:set_consider_megacrop()
   if not self._sv.consider_megacrop then
      self._sv.consider_megacrop = true
      self.__saved_variables:mark_changed()
   end
end

function AceCropComponent:apply_megacrop_chance_multiplier(multiplier)
   if multiplier ~= 1 and self._sv.megacrop_chance ~= 0 then
      self._sv.megacrop_chance = self._sv.megacrop_chance * multiplier
      self.__saved_variables:mark_changed()
   end
end

--- As we grow, change the resources we yield and, if appropriate, command harvest
AceCropComponent._ace_old__on_grow_period = CropComponent._on_grow_period
function AceCropComponent:_on_grow_period(e)
   local was_harvestable = self._sv.harvestable
   self:_ace_old__on_grow_period(e)
   
   -- if we just became harvestable, consider mega crop
   if was_harvestable ~= self._sv.harvestable and self._sv.consider_megacrop then
      if rng:get_real(0, 1) < self._sv.megacrop_chance then
         self:_set_megacrop()
      end
   end
end

function AceCropComponent:is_megacrop()
   return self._sv.is_megacrop
end

function AceCropComponent:_set_megacrop()
   self._sv.is_megacrop = true
   
   if self._megacrop_description then
      radiant.entities.set_description(self._entity, self._megacrop_description)
   end

   local render_info = self._entity:get_component('render_info')
   if self._megacrop_model_variant then
      self._entity:get_component('render_info'):set_model_variant(self._megacrop_model_variant)
   end
   render_info:set_scale(render_info:get_scale() * (2 + rng:get_real(-0.05, 0.05)))

   self.__saved_variables:mark_changed()
end

return AceCropComponent
