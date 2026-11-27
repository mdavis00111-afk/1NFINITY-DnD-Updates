extends RefCounted
## Informational dice only. Never changes a campaign, turn or actor.
const SIDES = [4,6,8,10,12,20,100]
const MAX_QUANTITY = 20

static func roll(sides: int, quantity: int) -> Dictionary:
	if sides not in SIDES or quantity < 1 or quantity > MAX_QUANTITY:
		return {}
	var values: Array[int] = []
	var total = 0
	for i in range(quantity):
		var value = randi_range(1,sides)
		values.append(value)
		total += value
	return {"sides":sides,"quantity":quantity,"values":values,"total":total}
