import 'package:flutter/material.dart';
import 'package:widget_and_text_animator/widget_and_text_animator.dart';

class OnlinePulsator extends StatelessWidget {
  const OnlinePulsator({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        WidgetAnimator(
          atRestEffect: WidgetRestingEffects.size(effectStrength: 0.5),
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.greenAccent.withOpacity(0.3)),
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent),
        ),
      ],
    );
  }
}
