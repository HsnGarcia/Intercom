package com.motointercom.moto_mesh_intercom

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.p2p.WifiP2pManager
import android.os.Looper

/**
 * Crea un grupo Wi-Fi Direct autónomo (Group Owner) para que otros Android e iOS
 * puedan intercambiar audio UDP sin internet ni activar Hotspot manualmente.
 */
class WifiDirectMeshManager(context: Context) {
    private val manager =
        context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private val channel: WifiP2pManager.Channel? =
        manager?.initialize(context, Looper.getMainLooper(), null)

    @SuppressLint("MissingPermission")
    fun ensureGroup(onResult: (Boolean, String?, String?) -> Unit) {
        val mgr = manager ?: return onResult(false, null, null)
        val ch = channel ?: return onResult(false, null, null)

        mgr.createGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                mgr.requestGroupInfo(ch) { group ->
                    onResult(true, group?.networkName, group?.passphrase)
                }
            }

            override fun onFailure(reason: Int) {
                // Si ya existe un grupo activo, devolvemos éxito parcial
                mgr.requestGroupInfo(ch) { group ->
                    if (group != null) {
                        onResult(true, group.networkName, group.passphrase)
                    } else {
                        onResult(false, null, null)
                    }
                }
            }
        })
    }

    fun leaveGroup() {
        val mgr = manager ?: return
        val ch = channel ?: return
        mgr.removeGroup(ch, null)
    }
}
