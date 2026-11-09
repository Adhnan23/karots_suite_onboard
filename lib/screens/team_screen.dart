import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../state.dart';
import '../sync/device_sync.dart';
import '../sync/team.dart';
import '../theme/tokens.dart';
import '../ui/kit.dart';

/// Your devices as one team: the same catalogue, suppliers and shops on each,
/// kept so by themselves on the same Wi-Fi while the app is open.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  String key = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context).store.read(teamKeyName).then((k) => mounted ? setState(() => key = k ?? '') : null);
  }

  Future<void> join(String k) async {
    final app = AppScope.of(context);
    final ok = await guard(context, () async {
      await app.setTeam(k);
      return true;
    });
    if (ok == true && mounted) setState(() => key = k.trim().toUpperCase());
  }

  Future<void> askKey() async {
    final ctl = TextEditingController();
    final k = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Join a team'),
        content: TextField(
          controller: ctl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Team key (KT-XXXX-XXXX-XXXX)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('Join')),
        ],
      ),
    );
    if (k != null && RegExp(r'^KT-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$').hasMatch(k.trim().toUpperCase())) {
      await join(k);
    } else if (k != null && mounted) {
      toast(context, 'A team key looks like KT-7F3Q-9XM2-PL4W', error: true);
    }
  }

  Future<void> addByAddress(TeamSync t) async {
    final ctl = TextEditingController();
    final a = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add a device by address'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(labelText: 'Its address (e.g. 10.61.223.227)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('Add')),
        ],
      ),
    );
    if (a == null || a.trim().isEmpty) return;
    final host = a.trim().split(':').first;
    t.addPeer('by-address-$host', host, SyncHost.defaultPort);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = KsTokens.of(context);
    final t = app.team;
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: Narrow(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Devices in a team keep the same catalogue, suppliers and shops: on the same Wi-Fi, while the app is open, every 2 minutes and soon after a change. Support secrets stay on each device (send them sealed under the key icon).',
              style: TextStyle(color: c.mutedForeground),
            ),
            const SizedBox(height: 16),
            if (key.isEmpty) ...[
              FilledButton.icon(onPressed: () => join(newTeamKey()), icon: const Icon(Icons.group_add_rounded), label: const Text('Make a team')),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: askKey, icon: const Icon(Icons.login_rounded), label: const Text('Join a team')),
            ] else ...[
              Section(
                title: 'Team key',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(key, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: key));
                          if (context.mounted) toast(context, 'Team key copied: type it on your other device');
                        },
                      ),
                    ],
                  ),
                  Text('Join with this on your other devices. Keep it to your team.', style: TextStyle(color: c.faint, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              Section(
                title: 'Devices',
                children: [
                  if (t == null) Text('Not running here: another app may be using its port.', style: TextStyle(color: c.danger)),
                  if (t != null && t.peers.isEmpty) Text('Looking for your other devices on this Wi-Fi…', style: TextStyle(color: c.mutedForeground)),
                  for (final p in t?.peers ?? <Peer>[])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(p.error.isEmpty ? Icons.devices_rounded : Icons.sync_problem_rounded, color: p.error.isEmpty ? c.success : c.danger),
                      title: Text(p.address),
                      subtitle: Text(
                        p.error.isNotEmpty
                            ? p.error
                            : p.lastSync == null
                            ? 'Found'
                            : 'Same as of ${DateFormat('HH:mm').format(p.lastSync!)}',
                      ),
                    ),
                  if (t != null)
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: t.syncing ? null : t.syncNow,
                          icon: const Icon(Icons.sync_rounded),
                          label: Text(t.syncing ? 'Syncing…' : 'Sync now'),
                        ),
                        OutlinedButton.icon(onPressed: () => addByAddress(t), icon: const Icon(Icons.add_rounded), label: const Text('Add by address')),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await app.setTeam(null);
                  if (mounted) setState(() => key = '');
                },
                child: Text('Leave the team', style: TextStyle(color: c.danger)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
