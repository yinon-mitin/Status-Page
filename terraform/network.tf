# Network foundation. It is disabled by default because applying it creates VPC resources.
# ALB is intentionally public; ECS tasks remain in internal application subnets.

resource "aws_vpc" "main" {
  count                = var.create_network ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.resource_tags, { Name = "${var.project}-${var.environment}" })
}

resource "aws_internet_gateway" "main" {
  count  = var.create_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  tags   = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-igw" })
}

resource "aws_subnet" "public" {
  for_each                = var.create_network ? var.availability_zones : {}
  vpc_id                  = aws_vpc.main[0].id
  availability_zone       = each.value
  cidr_block              = var.public_subnet_cidrs[each.key]
  map_public_ip_on_launch = false
  tags                    = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-public-${each.key}", Tier = "public" })
}

resource "aws_subnet" "app" {
  for_each          = var.create_network ? var.availability_zones : {}
  vpc_id            = aws_vpc.main[0].id
  availability_zone = each.value
  cidr_block        = var.app_subnet_cidrs[each.key]
  tags              = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-app-${each.key}", Tier = "internal-app" })
}

resource "aws_route_table" "public" {
  count  = var.create_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  tags   = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-public" })
}

resource "aws_route" "public_internet" {
  count                  = var.create_network ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

resource "aws_route_table_association" "public" {
  for_each       = var.create_network ? aws_subnet.public : {}
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

# Internal subnets deliberately have no direct Internet route or public IPs.
resource "aws_route_table" "app" {
  count  = var.create_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  tags   = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-internal-app" })
}

resource "aws_route_table_association" "app" {
  for_each       = var.create_network ? aws_subnet.app : {}
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[0].id
}

resource "aws_security_group" "alb" {
  count       = var.create_network ? 1 : 0
  name        = "${var.project}-${var.environment}-alb"
  description = "Internet ingress to the public Application Load Balancer."
  vpc_id      = aws_vpc.main[0].id
  tags        = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count             = var.create_network ? 1 : 0
  security_group_id = aws_security_group.alb[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count             = var.create_network ? 1 : 0
  security_group_id = aws_security_group.alb[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_security_group" "ecs" {
  count       = var.create_network ? 1 : 0
  name        = "${var.project}-${var.environment}-ecs"
  description = "ECS task ingress only from the ALB; data stores will reference this group."
  vpc_id      = aws_vpc.main[0].id
  tags        = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-ecs" })
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  count                        = var.create_network ? 1 : 0
  security_group_id            = aws_security_group.ecs[0].id
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}

# Egress remains open temporarily so future private RDS/Redis security groups
# can enforce the receiving-side least-privilege policy. This is tightened when
# the data layer is introduced.
resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  count             = var.create_network ? 1 : 0
  security_group_id = aws_security_group.ecs[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
