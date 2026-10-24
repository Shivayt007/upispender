package com.shivay.jarvisvoice

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

private val Background = Color(0xFF08141A)
private val Panel = Color(0xFF122B33)
private val Mint = Color(0xFF6AF0D0)
private val Pale = Color(0xFFD8E8EA)

class MainActivity : ComponentActivity() {
    private var refresh by mutableIntStateOf(0)
    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { refresh++ }

    override fun onResume() {
        super.onResume()
        refresh++
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val tick = refresh
            val prefs = remember { getSharedPreferences("jarvis", MODE_PRIVATE) }
            var whatsApp by remember { mutableStateOf(prefs.getBoolean("com.whatsapp", true)) }
            var telegram by remember { mutableStateOf(prefs.getBoolean("org.telegram.messenger", true)) }
            var instagram by remember { mutableStateOf(prefs.getBoolean("com.instagram.android", false)) }
            var sms by remember { mutableStateOf(prefs.getBoolean("sms", true)) }
            val notificationAccess = remember(tick) {
                Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                    ?.contains(packageName) == true
            }
            val micGranted = remember(tick) { has(Manifest.permission.RECORD_AUDIO) }
            val contactsGranted = remember(tick) { has(Manifest.permission.READ_CONTACTS) }
            val callsGranted = remember(tick) { has(Manifest.permission.CALL_PHONE) }
            val isRunning = remember(tick) { HandsFreeService.running }

            MaterialTheme(colorScheme = darkColorScheme(
                primary = Mint, background = Background, surface = Panel,
                onSurface = Pale, onBackground = Pale
            )) {
                Column(
                    modifier = Modifier.fillMaxSize().background(Background)
                        .verticalScroll(rememberScrollState()).padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Spacer(Modifier.height(12.dp))
                    Text("JARVIS", style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Bold, color = Mint)
                    Text("VOICE ASSISTANT  •  ENGLISH", color = Color(0xFF9DB5BC))
                    Card(colors = CardDefaults.cardColors(containerColor = Panel)) {
                        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(if (isRunning) "● Hands-free is listening" else "○ Hands-free is off",
                                color = if (isRunning) Mint else Pale,
                                fontWeight = FontWeight.SemiBold)
                            Text("Say: Hey Jarvis, wake up", color = Pale)
                            Text("Then say: Call Rahul, or Call that person.", color = Pale)
                            Text("Experimental when locked or screen-off; device restrictions apply.",
                                color = Color(0xFFADC0C6), style = MaterialTheme.typography.bodySmall)
                            Button(
                                onClick = {
                                    if (isRunning) {
                                        stopService(Intent(this@MainActivity, HandsFreeService::class.java))
                                    } else if (micGranted) {
                                        startForegroundService(Intent(this@MainActivity, HandsFreeService::class.java)
                                            .setAction(HandsFreeService.ACTION_START))
                                    }
                                    refresh++
                                },
                                enabled = micGranted,
                                modifier = Modifier.fillMaxWidth()
                            ) { Text(if (isRunning) "Stop hands-free" else "Start hands-free") }
                            OutlinedButton(
                                onClick = { VoiceSpeaker.say(this@MainActivity, "Hello, I am Jarvis. At your service.") },
                                modifier = Modifier.fillMaxWidth()
                            ) { Text("Test English voice") }
                        }
                    }
                    Text("1  •  PERMISSIONS", fontWeight = FontWeight.Bold)
                    SetupItem("Notification access", notificationAccess,
                        "Required to hear message previews") {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    }
                    SetupItem("Microphone", micGranted, "For hands-free voice commands") {
                        permissionLauncher.launch(arrayOf(Manifest.permission.RECORD_AUDIO))
                    }
                    SetupItem("Contacts", contactsGranted, "Match the sender to a phone number") {
                        permissionLauncher.launch(arrayOf(Manifest.permission.READ_CONTACTS))
                    }
                    SetupItem("Phone calling", callsGranted, "Required for normal SIM calls") {
                        permissionLauncher.launch(arrayOf(Manifest.permission.CALL_PHONE))
                    }
                    if (Build.VERSION.SDK_INT >= 33) {
                        SetupItem("Notifications", has(Manifest.permission.POST_NOTIFICATIONS),
                            "Show the active microphone indicator") {
                            permissionLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
                        }
                    }
                    Text("2  •  MESSAGES TO SPEAK", fontWeight = FontWeight.Bold)
                    SettingSwitch("WhatsApp", whatsApp) {
                        whatsApp = it; prefs.edit().putBoolean("com.whatsapp", it).apply()
                    }
                    SettingSwitch("Telegram", telegram) {
                        telegram = it; prefs.edit().putBoolean("org.telegram.messenger", it).apply()
                    }
                    SettingSwitch("Instagram", instagram) {
                        instagram = it; prefs.edit().putBoolean("com.instagram.android", it).apply()
                    }
                    SettingSwitch("SMS", sms) {
                        sms = it; prefs.edit().putBoolean("sms", it).apply()
                    }
                    Text("PRIVACY & LIMITATIONS", fontWeight = FontWeight.Bold)
                    Text(
                        "Notification text is spoken locally. No messages are uploaded by this app. " +
                        "Your installed speech recognition engine may use network services. " +
                        "Screen-off listening is experimental and uses battery. " +
                        "Voice confirmation is not speaker authentication. Do not use in public environments.",
                        color = Color(0xFFA9C0C6), style = MaterialTheme.typography.bodySmall
                    )
                    Spacer(Modifier.height(18.dp))
                }
            }
        }
    }

    private fun has(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
}

@Composable
private fun SetupItem(title: String, granted: Boolean, detail: String, onClick: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = Panel)) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.SemiBold)
                Text(detail, style = MaterialTheme.typography.bodySmall,
                    color = Color(0xFFB1C3C7))
            }
            TextButton(onClick = onClick) { Text(if (granted) "Enabled" else "Enable") }
        }
    }
}

@Composable
private fun SettingSwitch(name: String, enabled: Boolean, onChanged: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().background(Panel, MaterialTheme.shapes.medium).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(name, modifier = Modifier.weight(1f), fontWeight = FontWeight.Medium)
        Switch(checked = enabled, onCheckedChange = onChanged)
    }
}
