## LibThingsLoad

Library for load quests, items and spells.

### Usage

```lua
local ltl = LibStub("LibThingsLoad-1.0")
-- Create Quest Promise
local promise = ltl:Quests(25, 2039, 2158, 37) -- or table of ids ltl:Quests({25, 2039, 2158, 37})
-- or create Item Promise
local promise = ltl:Items(3069, 1537, 1539, 3081) -- or table of ids ltl:Items({3069, 1537, 1539, 3081})
-- or create Spell Promise
local promise = ltl:Spells(1557, 3117, 3229, 1645) -- or table of ids ltl:Spells({1557, 3117, 3229, 1645})

promise:Then(function(promise) -- the callback will be called when all IDs have been loaded
    -- some code
end)
promise:ThenForAll(function(promise, id, loadType) -- the callback will be called for any loaded id
   -- some code
end)
promise:ThenForAllWithCached(function(promise, id, loadType) -- the callback will be called for any loaded or cached id
   -- some code
end)
promise:Fail(function(promise, id, loadType) -- the callback will be called for any unsuccessfully loaded id
   -- some code
end)
promise:FailWithChecked(function(promise, id, loadType) -- the callback will be called for any failed id loaded or already failed id loaded
   -- some code
end)
```

[API](https://github.com/sfmict/LibThingsLoad/wiki/API)
