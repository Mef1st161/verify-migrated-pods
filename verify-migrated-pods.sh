#!/bin/bash

# файл из вывода kubectl get pod -A -o wide до дрейна
INPUT="pods-before-drain.txt"

# Очистим мусор
grep -E "^[a-z]" "$INPUT" | while read -r line; do
  NS=$(echo "$line" | awk '{print $1}')
  POD_FULL=$(echo "$line" | awk '{print $2}')
  NODE=$(echo "$line" | awk '{print $7}')

  # Пропускаем системные поды, если хочешь — удали этот блок
  if [[ "$NS" =~ ^(kube-system|logs|monitoring|vector|velero|ciliumping)$ ]]; then
    continue
  fi

  # Получаем префикс (имя ReplicaSet): убираем последний суффикс после "-"
  PREFIX=$(echo "$POD_FULL" | sed 's/-[a-z0-9]*$//')

  # Ищем активные поды с этим префиксом НЕ на worker
  CURRENT=$(kubectl get pods -n "$NS" -o wide 2>/dev/null | grep "^$PREFIX" | grep -v "worker" | awk '{print $1 " на " $7 " (" $3 ")"}')

  if [ -n "$CURRENT" ]; then
    echo "✅ $NS/$POD_FULL → $CURRENT"
  else
    # Проверим, может, он вообще исчез?
    EXISTS_ANY=$(kubectl get pods -n "$NS" -o name 2>/dev/null | grep -F "$PREFIX")
    if [ -z "$EXISTS_ANY" ]; then
      echo "❌ $NS/$POD_FULL → НЕ НАЙДЕН (возможно, не восстановлен!)"
    else
      # Есть, но всё ещё на worker6?
      ON_WORKER6=$(kubectl get pods -n "$NS" -o wide 2>/dev/null | grep "^$PREFIX" | grep "worker6")
      if [ -n "$ON_WORKER6" ]; then
        echo "⚠️  $NS/$POD_FULL → всё ещё на worker6: $(echo $ON_WORKER6 | awk '{print $3}')"
      else
        echo "❓ $NS/$POD_FULL → странное состояние, проверь вручную"
      fi
    fi
  fi
done
