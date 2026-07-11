-----------------------------------------------------------
-- rde_phone / data / items.lua
-- ox_inventory item export handler.
-- Register the item on the ox_inventory side (data/items.lua there) with:
--
--   ['phone'] = {
--       label = 'Phone',
--       weight = 190,
--       stack = false,
--       close = true,
--       client = {
--           export = 'rde_phone.use_phone',
--       },
--   },
-----------------------------------------------------------

local function UsePhoneItem(data, slot)
    TriggerEvent('rde_phone:client:tryOpen')
end

exports('use_phone', UsePhoneItem)
