class_name CBLayers
extends RefCounted
## Canonical collision layers for CUBE BOX (all modes).
## Only the necessary things detect each other:
##  bit 1 (value 1) = WORLD static (ground / voxels / pillars)
##  bit 2 (value 2) = PLAYER CharacterBody / fighter proxy
##  bit 3 (value 4) = ENEMY (ow_enemy body, goomba)
##  bit 4 (value 8) = PICKUP (unused by physics; manual distance checks)
##  bit 5 (value 16) = PROJECTILE (visual only; manual distance checks)
##
## Masks are deliberately minimal so the physics broadphase does almost no
## pair tests. Projectiles / coins / props use manual flat-distance checks.

const WORLD: int = 1
const PLAYER: int = 2
const ENEMY: int = 4
const PICKUP: int = 8
const PROJECTILE: int = 16

const MASK_STATIC: int = 0
const MASK_PLAYER: int = WORLD
const MASK_ENEMY: int = WORLD
const MASK_SENSOR: int = 0


static func apply_static(body: StaticBody3D) -> void:
	body.collision_layer = WORLD
	body.collision_mask = MASK_STATIC


static func apply_player(body: CollisionObject3D) -> void:
	body.collision_layer = PLAYER
	body.collision_mask = MASK_PLAYER


static func apply_enemy(body: CollisionObject3D) -> void:
	body.collision_layer = ENEMY
	body.collision_mask = MASK_ENEMY
