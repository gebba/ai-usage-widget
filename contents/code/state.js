.pragma library

function formatPercent(value) {
    if (value === null || value === undefined || isNaN(value)) {
        return "—";
    }
    return Math.round(Number(value)) + " %";
}

function limitColor(value) {
    if (value === null || value === undefined || isNaN(value)) {
        return "#9aa0a6";
    }
    value = Number(value);
    if (value < 25) return "#ff5f57";
    if (value < 75) return "#f2c94c";
    return "#35c46b";
}

function severityColor(value, theme) {
    return limitColor(value);
}

function localPath(pathOrUrl) {
    if (!pathOrUrl) return "";
    var value = String(pathOrUrl);
    if (value.indexOf("file://") === 0) {
        value = value.substring(7);
    }
    return decodeURIComponent(value);
}

function pad2(value) {
    return value < 10 ? "0" + value : "" + value;
}

function shortMonth(index) {
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][index] || "";
}

function shortWeekday(index) {
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index] || "";
}

function resetText(resetAt, windowSeconds) {
    if (!resetAt) return "";
    var d = new Date(resetAt);
    if (isNaN(d.getTime())) return "";

    if (Number(windowSeconds) === 18000) {
        var totalMinutes = Math.max(0, Math.round((d.getTime() - Date.now()) / 60000));
        var hours = Math.floor(totalMinutes / 60);
        var minutes = totalMinutes % 60;
        if (hours <= 0) return "Resets in " + minutes + "m";
        if (minutes === 0) return "Resets in " + hours + "h";
        return "Resets in " + hours + "h " + minutes + "m";
    }

    return "Resets " + shortWeekday(d.getDay()) + ", " + shortMonth(d.getMonth()) + " " + d.getDate() + " at " + pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function freshnessText(updatedAt) {
    if (!updatedAt) return "Never updated";
    var d = new Date(updatedAt);
    if (isNaN(d.getTime())) return "Updated time unknown";
    return "Updated " + shortWeekday(d.getDay()) + ", " + shortMonth(d.getMonth()) + " " + d.getDate() + " at " + pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}
