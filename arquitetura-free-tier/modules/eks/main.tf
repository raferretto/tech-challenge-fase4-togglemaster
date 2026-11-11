# --- Suporte a AWS Academy (LabRole) vs Conta Pessoal ---
data "aws_iam_role" "lab_role" {
  count = var.use_aws_academy ? 1 : 0
  name  = "LabRole"
}

# --- IAM Roles para Conta Pessoal ---
# Role do Cluster EKS (Control Plane)
resource "aws_iam_role" "cluster" {
  count = var.use_aws_academy ? 0 : 1
  name  = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count      = var.use_aws_academy ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster[0].name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  count      = var.use_aws_academy ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster[0].name
}

# Role para os Worker Nodes
resource "aws_iam_role" "nodes" {
  count = var.use_aws_academy ? 0 : 1
  name  = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  count      = var.use_aws_academy ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes[0].name
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  count      = var.use_aws_academy ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes[0].name
}

resource "aws_iam_role_policy_attachment" "node_registry_policy" {
  count      = var.use_aws_academy ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes[0].name
}

# Definição das ARNs utilizadas conforme o modo (Academy vs Pessoal)
locals {
  cluster_role_arn = var.use_aws_academy ? data.aws_iam_role.lab_role[0].arn : aws_iam_role.cluster[0].arn
  node_role_arn    = var.use_aws_academy ? data.aws_iam_role.lab_role[0].arn : aws_iam_role.nodes[0].arn
}

# --- Cluster EKS ---
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = local.cluster_role_arn

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [var.cluster_security_group_id]
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller
  ]

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )
}

# --- EKS Managed Node Group ---
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = local.node_role_arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.desired_nodes
    max_size     = var.max_nodes
    min_size     = var.min_nodes
  }

  instance_types = var.node_instance_types

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_registry_policy
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-node-group"
    }
  )
}

# --- OIDC Provider para IAM Roles for Service Accounts (IRSA) ---
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

# --- Add-ons Básicos do EKS ---
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  depends_on   = [aws_eks_node_group.main]
}
