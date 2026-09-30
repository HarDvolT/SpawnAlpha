import 'coaching_style.dart';
import 'script_document.dart';
import 'script_language.dart';

/// One sample script per coaching style, one per language, so a new user
/// can try the markup and the prompter straight away.
List<ScriptDocument> sampleScripts() => [
      ScriptDocument.create(
        title: 'Sample: quarterly update',
        language: ScriptLanguage.en,
        style: CoachingStyle.presentation,
        text: 'Last quarter, our support team answered 12,000 tickets. '
            'That is twice as many as the year before, with the same team.\n\n'
            'So how did we do it? We stopped answering the same question twice. '
            'Every answer now goes into a shared library, and the next person who asks gets it in seconds.\n\n'
            'Today I want to show you three things: what we built, what it changed, and what we need from you next.',
      ),
      ScriptDocument.create(
        title: 'Exemple : exporter une vidéo',
        language: ScriptLanguage.fr,
        style: CoachingStyle.tutorial,
        text: 'Dans cette vidéo, je vais vous montrer comment exporter votre montage en haute qualité.\n\n'
            "D'abord, ouvrez le menu Fichier et choisissez Exporter.\n"
            'Ensuite, sélectionnez le format MP4 et réglez le débit sur 20 Mbps.\n'
            'Puis cliquez sur Enregistrer et choisissez un dossier.\n'
            "Enfin, attendez la fin de l'export avant de fermer l'application.\n\n"
            "C'est tout ! Votre vidéo est prête à être partagée.",
      ),
      ScriptDocument.create(
        title: 'مثال: نصيحة سريعة',
        language: ScriptLanguage.ar,
        style: CoachingStyle.shortSocial,
        text: 'توقف! هل تعرف أن معظم الناس يضيعون ساعتين يومياً على هواتفهم دون أن يشعروا؟\n'
            'جرب هذه الحيلة البسيطة: أطفئ كل الإشعارات غير المهمة لمدة أسبوع واحد فقط.\n'
            'ستتفاجأ بكمية الوقت التي ستستعيدها.\n'
            'تابعني لمزيد من النصائح التي تغير يومك.',
      ),
    ];
