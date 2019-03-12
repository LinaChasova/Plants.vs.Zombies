{-# OPTIONS_GHC -Wall -fdefer-typed-holes #-}
{-# LANGUAGE OverloadedStrings #-}

module Update where

import Type
import Utils
import Settings
import Structure.Object

-- | High-level function to attack zombie/plants
attack
  :: (a -> b -> b)  -- ^ function that changes zombie/plant
  -> [a]            -- ^ zombies/plants that may affect plant/zombie
  -> b              -- ^ zomvie/plant to affect
  -> b
attack _f [] b      = b
attack f (x : xs) b = attack f xs (f x b)

-- | Function to perform updates on zombie, according
-- to time passed in the game. Move zombie, if there's
-- no collision with the plant, reduce health of the
-- zombie, if there's collision with the plant's 
-- projectile.
updateZombies :: Float -> Universe -> [Zombie]
updateZombies dt u = update zs  
  where
    update = map (updateZombie dt u)
           . deleteZombie
           . map (attackZombie dt u)
    zs     = uEnemies u  

-- | Function to update one zombie in terms of moving zombie
-- further or not. It checks the collision with the plants:
-- defense plants and sunflowers and moves zombie further
-- if there's no collision, otherwise it stays at the same
-- place.
updateZombie :: Float -> Universe -> Zombie -> Zombie
updateZombie dt u z
  | True `elem` collisions = bitePlant dt z
  | otherwise              = moveZombie dt z
  where
    plantsXY     = map (pCoords) (uDefense u)
    sunflowersXY = map (sCoords) (uSunflowers u)
    collisions   = pCollisions ++ sCollisions
      where
        pCollisions = map (checkCollision (zCoords z)) plantsXY
        sCollisions = map (checkCollision (zCoords z)) sunflowersXY

-- | Function to bite plant
--   lowers seconds till the bite, if they are larger than 0
--   assigns new timer if they are less than zero
bitePlant :: Float -> Zombie -> Zombie
bitePlant dt z
  | seconds <= 0 = z
      { zSeconds = 1 }
  | otherwise    = z
      { zSeconds = seconds }
  where
    seconds = zSeconds z - dt

-- | Function to move zombie further, dt is the time
-- passed from last update (since zombie was last
-- moved). dt * v - denotes how much zombie should
-- be moved. and we subtract it from the original
-- x coordinate, because zombie is going to the negative x
moveZombie :: Float -> Zombie -> Zombie
moveZombie dt z = z { zCoords = (x - dt * v, y) }
  where
    (x, y) = zCoords z
    v      = zSpeed  (zType z)

-- | Function to lower health of zombies
--   iterate through plants and lower health
--   if collision with its projectile happened
attackZombie :: Float -> Universe -> Zombie -> Zombie
attackZombie dt u = attack (reduceHealthZombie dt) prs
  where
    prs = concat (map (\p -> 
          (zip (repeat (pStrength (pType p))) (pBullet p))) ps)
    ps  = uDefense u

-- | Function to reduce health of zombie
--   by checking the collision with the projectiles
reduceHealthZombie :: Float -> (Int, Projectile) -> Zombie -> Zombie
reduceHealthZombie dt (strength, pr) z
  | checkCollision zXY prXY = newZombie 
  | otherwise = z
  where 
    zXY        = zCoords z
    prXY       = prCoords pr
    newZombie  = z 
     { zDamage = zDamage z + strength }

-- | Function to remove zombie from the game
-- if its health is less than the damage the
-- current zombie received.
deleteZombie :: [Zombie] -> [Zombie]
deleteZombie zs = filter (hasHealth) zs
  where
    hasHealth z = (zDamage z) <= (zHealth (zType z))

-- | Function to update plant according to time passed.
--   It corresponds to lowering the health of the plant,
--   if zombie is currently in collision with plant.
--   Removing plants, if it has no health any more.
--   Shooting with the peas, if it seas the zombie.
--   Move projectiles
updatePlants :: Float -> Universe -> [Plant]
updatePlants dt u = update ps                     
  where
    update = deletePlant
           . map (attackPlant u)
           . updateProjectiles dt u
    ps     = uDefense u

-- | Function to lower health of plants
--   iterate through zombies and lower health
--   if their timer for bite is exceed
attackPlant :: Universe -> Plant -> Plant
attackPlant u = attack reduceHealthPlant zs
  where
    zs = uEnemies u

-- | Function to reduce health of plant
--   reduce health of the plant if there's
--   collision with zombie and their timer
--   till bite is up
reduceHealthPlant :: Zombie -> Plant -> Plant
reduceHealthPlant z p
  | not (checkCollision zXY pXY) = p
  | seconds <= 0                 = newP
  | otherwise                    = p
  where
    seconds     = zSeconds z
    zXY         = zCoords z
    pXY         = pCoords p
    newP        = p
      { pDamage = (pDamage p) + (zStrength (zType z)) }

-- | Function to remove plant from the game
--   if its health is less than the damage the
--   current plant received.
deletePlant :: [Plant] -> [Plant]
deletePlant ps = filter (hasHealth) ps
  where
    hasHealth p = (pDamage p) <= (pHealth (pType p))

-- | Function to update projectile by the time passed
-- * Perform shooting of projectile;
-- * Perform moving projectile along x-axis
-- * Perform deleting projectile
updateProjectiles :: Float -> Universe -> [Plant] -> [Plant]
updateProjectiles dt u = update
  where
    update = map (shootProjectile dt u)
           . map (moveProjectiles dt)
           . map (deleteProjectile u)
    
-- | Function to shoot projectile
-- * if there's no zombie in pea vision -> no shooting performed
--   seconds to the next shooting is put to zero
-- * if time to the next shoot is less or equal to zero,
--   plant generates new projectile
-- * otherwise lower time till shooting
shootProjectile :: Float -> Universe -> Plant -> Plant
shootProjectile dt u p
  | not (any (peaVision (pCoords p) screenWidth) zs) = p
                                          { pSeconds = 0 }
  | seconds <= 0                                     = p
                                          { pBullet  = shoot
                                          , pSeconds = 5
                                          }
  | otherwise                                        = p
                                          { pSeconds = seconds }
  where
    shoot     = newBullet : bullet
    seconds   = pSeconds p - dt 
    newBullet = Projectile (x + 20, y)
    (x, y)    = pCoords p
    bullet    = pBullet p
    zs        = uEnemies u

-- | Checks if Pea sees Zombie, by comparing their y-axis coordinates
--   and getting into the account that zombie should be seen
--   only in the game border
peaVision
  :: Coords -- ^ Coordinates of Pea's eyes
  -> Int
  -> Zombie -- ^ Zombie to check
  -> Bool -- ^ True if sees Flase otherwise
peaVision (_, y) screenBorder zombie = checkVision (zCoords zombie)
  where
    checkVision (zX, zY) = y == zY && zX < fromIntegral screenBorder

-- | Function to move projectiles of the plant, by the
--   delta time * speed of the projectile
moveProjectiles :: Float -> Plant -> Plant
moveProjectiles dt p = p { pBullet = move }
  where
    move = map (moveProjectile dt) b
    b    = pBullet p

moveProjectile :: Float -> Projectile -> Projectile
moveProjectile dt pr = Projectile (x + dt * 30, y)
  where
    (x, y) = prCoords pr

-- | Fucntion to delete projectile from the plant
-- * Delete if projectile moved out of the game border
-- * Delete if projectile has collision with the zombie
deleteProjectile :: Universe -> Plant -> Plant
deleteProjectile u p = p { pBullet = delete prs }
  where
    delete          = filter (hasCollision)
                    . filter (outOfBorder)
    prs             = pBullet p
    zs              = uEnemies u
    outOfBorder pr  = fst (prCoords pr) < endingCoords
    hasCollision pr = not (True `elem` collisions)
      where
        zombiesXY  = map (zCoords) zs
        collisions = map (checkCollision (prCoords pr)) zombiesXY

-- | Function to update sunflower by the time passed
-- * produce sun
-- * reduce health of the sunflower
-- * delete sunflower
updateSunflowers :: Float -> Universe -> [Sunflower]
updateSunflowers dt u = update sfs  
  where
    update = map (sendSun dt)
           . deleteSunflower
           . map (attackSunflower u)
    sfs    = uSunflowers u

-- | Function that produces sun from sunflower
-- * if seconds left is less than zero ->
--   produce sun
-- * otherwise lower time till creation of sun
sendSun :: Float -> Sunflower -> Sunflower
sendSun dt sf
  | seconds <= 0 = sf
      { sSun     = send
      , sSeconds = 5
      }
  | otherwise    = sf
      { sSeconds = seconds }
  where
    seconds = sSeconds sf - dt
    send    = newSun : oldSuns
    (x, y)  = sCoords sf 
    newSun  = Sun (x + 50, y - 30)
    oldSuns = sSun sf

-- | Function to lower health of sunflowers
--   iterate through zombies and lower health
--   if their timer for bite is exceed
attackSunflower :: Universe -> Sunflower -> Sunflower
attackSunflower u sf = attack reduceHealthSunflower zs sf
  where
    zs = uEnemies u

-- | Function to reduce health of sunflower
--   reduce health of the sunflower if there's
--   collision with zombie and their timer
--   till bite is up
reduceHealthSunflower :: Zombie -> Sunflower -> Sunflower
reduceHealthSunflower z sf
  | not (checkCollision zXY sfXY) = sf
  | seconds <= 0                  = newSf
  | otherwise      = sf
  where
    seconds     = zSeconds z
    zXY         = zCoords z
    sfXY        = sCoords sf
    newSf       = sf
      { sDamage = (sDamage sf) + (zStrength (zType z)) }

-- | Function to remove sunflower from the game
--   if its health is less than the damage the
--   current sunflower received.
deleteSunflower :: [Sunflower] -> [Sunflower]
deleteSunflower = filter (hasHealth)
  where
    hasHealth s = (sDamage s) <= (sHealth  s)
