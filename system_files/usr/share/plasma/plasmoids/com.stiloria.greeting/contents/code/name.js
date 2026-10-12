.pragma library

// The name the greeting uses: the first word of the account's full name, or,
// for an account without one, the login name with a capital letter. KUser
// gives the login name as the full name of such an account.
function firstName(fullName, loginName) {
    const login = (loginName || "").trim();
    const full = (fullName || "").trim();
    if (full && full !== login) {
        return full.split(/\s+/)[0];
    }
    return login.charAt(0).toUpperCase() + login.slice(1);
}
