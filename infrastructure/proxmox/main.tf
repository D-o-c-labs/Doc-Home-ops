#module "onepassword_item_proxmox" {
#  source = "github.com/bjw-s/terraform-1password-item?ref=main"
#  vault  = "Automation"
#  item   = "proxform"
#}

# Handles creating the VMs in Proxmox for a Talos Cluster.
# Does NOT bootstrap the cluster.
module "talos" {
    source = "./modules/talos"
    proxmox_host_node = var.proxmox_host_node
    proxmox_api_url = var.proxmox_api_url
    proxmox_api_token_id = var.proxmox_api_token_id
    proxmox_api_token_secret = var.proxmox_api_token_secret
    ceph_mon_disk_storage_pool = "local-lvm"
    proxmox_debug = true
}

output "control_plane_mac_addrs" {
    value = module.talos.control_plane_config_mac_addrs
}

output "worker_mac_addrs" {
    value = module.talos.worker_node_config_mac_addrs
}