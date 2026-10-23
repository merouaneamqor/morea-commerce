# frozen_string_literal: true

module Morea
  # Copy for the "Our story" page (slug "about"), one body per locale.
  module OurStory
    TITLES = { "fr" => "Notre histoire", "en" => "Our story", "ar" => "قصتنا" }.freeze

    BODIES = {
      "en" => <<~TEXT.strip,
        Move with Purpose.

        MOREA was born from a simple belief: every woman deserves to move freely, feel confident, and express her style without compromising her values.

        We believe modesty and movement belong together. That elegance, comfort, and performance should never be a choice between one or the other.

        Designed for Movement. Made for You.

        At MOREA, we create modest activewear that empowers women to embrace an active lifestyle with confidence.

        From morning walks and Pilates sessions to everyday adventures, our pieces are designed to move with you, offering the perfect balance of coverage, comfort, and effortless elegance.

        Every detail has a purpose. Every design celebrates the woman wearing it.

        Modesty Is Our Strength.

        We see modesty not as a limitation, but as a form of self-expression.

        Our vision is to redefine modest sportswear through timeless designs, versatile silhouettes, and thoughtful details that allow women to feel comfortable and beautiful in their own way.

        Proudly Moroccan. Inspired by Women Everywhere.

        Rooted in Morocco and inspired by modern women, MOREA celebrates individuality, ambition, and confidence.

        We're building more than an activewear brand. We're creating a community of women who believe in moving forward, staying true to themselves, and embracing every step of their journey.

        More Than Activewear. A Mindset.

        Whether you're beginning your fitness journey, chasing a personal goal, or simply embracing an active lifestyle, MOREA is here to move with you.

        Move freely. Feel confident. Stay true to yourself.

        MOREA — Move with Purpose.
      TEXT
      "fr" => <<~TEXT.strip,
        Avancer avec intention.

        MOREA est née d'une conviction simple : chaque femme mérite de bouger librement, de se sentir en confiance et d'exprimer son style sans renoncer à ses valeurs.

        Nous croyons que pudeur et mouvement vont de pair. Que l'élégance, le confort et la performance ne doivent jamais être un choix entre l'un ou l'autre.

        Conçue pour le mouvement. Faite pour vous.

        Chez MOREA, nous créons des tenues de sport pudiques qui permettent aux femmes d'adopter un mode de vie actif en toute confiance.

        Des marches du matin aux séances de Pilates, en passant par les aventures du quotidien, nos pièces sont pensées pour vous suivre, avec le juste équilibre entre couverture, confort et élégance naturelle.

        Chaque détail a une raison d'être. Chaque design célèbre la femme qui le porte.

        La pudeur est notre force.

        Nous ne voyons pas la pudeur comme une limite, mais comme une forme d'expression de soi.

        Notre vision : redéfinir le sportswear pudique grâce à des designs intemporels, des silhouettes polyvalentes et des détails soignés qui permettent à chaque femme de se sentir à l'aise et belle à sa façon.

        Fièrement marocaine. Inspirée par les femmes du monde entier.

        Ancrée au Maroc et inspirée par les femmes d'aujourd'hui, MOREA célèbre l'individualité, l'ambition et la confiance en soi.

        Nous construisons plus qu'une marque de sport. Nous créons une communauté de femmes qui avancent, restent fidèles à elles-mêmes et vivent pleinement chaque étape de leur parcours.

        Plus qu'une tenue de sport. Un état d'esprit.

        Que vous débutiez votre parcours sportif, poursuiviez un objectif personnel ou adoptiez simplement un mode de vie actif, MOREA vous accompagne.

        Bougez librement. Sentez-vous en confiance. Restez fidèle à vous-même.

        MOREA — Avancer avec intention.
      TEXT
      "ar" => <<~TEXT.strip
        تحرّكي بهدف.

        وُلدت موريا من إيمان بسيط: كل امرأة تستحق أن تتحرك بحرية، وأن تشعر بالثقة، وأن تعبّر عن أسلوبها دون التخلي عن قيمها.

        نؤمن بأن الاحتشام والحركة يسيران معاً، وأن الأناقة والراحة والأداء لا ينبغي أن تكون خياراً بين أحدها والآخر.

        مصممة للحركة. صُنعت لكِ.

        في موريا نبتكر ملابس رياضية محتشمة تمنح النساء القدرة على عيش نمط حياة نشيط بثقة.

        من المشي الصباحي وحصص البيلاتس إلى مغامرات الحياة اليومية، صُممت قطعنا لتتحرك معكِ، بتوازن مثالي بين التغطية والراحة والأناقة العفوية.

        لكل تفصيل غاية، وكل تصميم يحتفي بالمرأة التي ترتديه.

        الاحتشام قوتنا.

        لا نرى الاحتشام قيداً، بل شكلاً من أشكال التعبير عن الذات.

        رؤيتنا إعادة تعريف الملابس الرياضية المحتشمة بتصاميم خالدة وقصّات متعددة الاستعمالات وتفاصيل مدروسة تتيح لكل امرأة أن تشعر بالراحة والجمال على طريقتها.

        فخورة بمغربيتها. مستوحاة من نساء العالم.

        متجذرة في المغرب ومستوحاة من المرأة العصرية، تحتفي موريا بالتميّز والطموح والثقة بالنفس.

        نحن لا نبني علامة رياضية فحسب، بل نصنع مجتمعاً من النساء اللواتي يؤمنّ بالمضي قدماً والبقاء وفيّات لأنفسهن وعيش كل خطوة من رحلتهن.

        أكثر من ملابس رياضية. عقلية.

        سواء كنتِ في بداية رحلتك الرياضية، أو تسعين لتحقيق هدف شخصي، أو تعتمدين ببساطة نمط حياة نشيطاً، فموريا معكِ في كل خطوة.

        تحرّكي بحرية. اشعري بالثقة. كوني وفية لنفسك.

        موريا — تحرّكي بهدف.
      TEXT
    }.freeze
  end
end
